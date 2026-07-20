#!/usr/bin/env bash
# add_whitelists.sh — manage Postfix & Postgrey client allowlists on Mail-in-a-Box
#
# Purpose: DELIVERABILITY. Trusted clients bypass greylisting at both levels:
#   Postfix maps (hash + cidr) act first; the Postgrey .local file is the
#   redundant second layer that survives MIAB updates detaching the maps.
#
# Note: entries match the CONNECTING CLIENT (rDNS hostname / IP address),
# not the From: header — that is how check_client_access works.
#
# Routing:
#   Domain     → Postfix hash (entry OK) + Postgrey (entry)
#   IPv4       → Postfix hash (entry OK) + Postgrey (entry)
#   IPv6       → Postfix cidr-map (entry OK) + Postgrey (entry)
#   CIDR v4/v6 → Postfix cidr-map (entry OK) + Postgrey (entry)
#
# Usage:
#   ./add_whitelists.sh example.com
#   ./add_whitelists.sh 1.2.3.4
#   ./add_whitelists.sh 198.51.100.0/24
#   ./add_whitelists.sh 2001:db8::/32
#   ./add_whitelists.sh -f whitelists.txt
#   ./add_whitelists.sh -n -f whitelists.txt      # dry-run
#   ./add_whitelists.sh --best-effort -f FILE     # apply valid lines even if some are invalid
#   ./add_whitelists.sh --setup                   # wire maps into Postfix restrictions
#   ./add_whitelists.sh --check                   # verify integration + ordering
#   ./add_whitelists.sh --list                    # show current whitelist contents
#   ./add_whitelists.sh --remove ENTRY            # remove an entry from all whitelists
#   ./add_whitelists.sh --verify ENTRY            # is this entry actually whitelisted?
#   ./add_whitelists.sh --version
#
# Exit codes: 0 success, 1 usage/runtime error, 2 validation failed

set -Eeuo pipefail

VERSION="2.4"

POSTFIX_FILE="/etc/postfix/client_whitelist"
CIDR_FILE="/etc/postfix/client_whitelist_cidr"
POSTGREY_FILE="/etc/postgrey/whitelist_clients.local"
BACKUP_DATE="$(date +%F_%H%M%S)"
BACKUP_RETENTION_DAYS=30

HASH_TOKEN="check_client_access hash:${POSTFIX_FILE}"
CIDR_TOKEN="check_client_access cidr:${CIDR_FILE}"

# --- logging ---
LOG_FILE="/var/log/add_whitelists.log"
# If we can prepare the log file, we log; otherwise continue silently (no crash).
LOG_ENABLED=0
prepare_log() {
  local dir
  dir="$(dirname "$LOG_FILE")"
  if mkdir -p "$dir" 2>/dev/null; then
    # 0640 root:adm (or root:root if adm missing)
    touch "$LOG_FILE" 2>/dev/null || return 0
    chown root:adm "$LOG_FILE" 2>/dev/null || true
    chmod 0640 "$LOG_FILE" 2>/dev/null || true
    LOG_ENABLED=1
  fi
}
log_line() {
  # printf '%(...)T' is a bash builtin — no date(1) fork per log line,
  # which matters on bulk imports (2 log calls per entry).
  local ts user msg
  printf -v ts '%(%F %T)T' -1
  user="${SUDO_USER:-${USER:-root}}"
  msg="$*"
  if [ "$LOG_ENABLED" -eq 1 ]; then
    printf '%s [%s] %s\n' "$ts" "$user" "$msg" >> "$LOG_FILE" || true
  fi
}

usage() {
  cat <<'EOF'
Usage:
  add_whitelists.sh [-n] [--best-effort] <domain-or-ip-or-cidr>
  add_whitelists.sh [-n] [--best-effort] -f <file_with_entries>
  add_whitelists.sh --setup     Wire whitelist maps into Postfix (idempotent)
  add_whitelists.sh --check     Verify Postfix integration and ordering
  add_whitelists.sh --list      Show current whitelist contents and counters
  add_whitelists.sh --remove ENTRY   Remove an entry from all whitelist files
  add_whitelists.sh --verify ENTRY   Check whether an entry is actually whitelisted
  add_whitelists.sh --version   Show script version

Options:
  -f FILE         File with entries (one per line; empty lines and #comments ignored)
  -n              Dry-run (no changes applied)
  -h              Show this help
  --best-effort   Apply valid entries even if the batch contains invalid ones
                  (default: validate the whole batch first, abort on any error)

Routing:
  Domain       -> Postfix hash + Postgrey
  IPv4         -> Postfix hash + Postgrey
  IPv6         -> Postfix cidr-map + Postgrey
  CIDR v4/v6   -> Postfix cidr-map + Postgrey

Exit codes:
  0 success, 1 usage/runtime error, 2 validation failed

NOTE: Postfix maps take effect only after --setup has been run once
      (adds check_client_access to smtpd_recipient_restrictions).
      Postgrey whitelisting works regardless of --setup.
EOF
  exit 1
}

# --- light coloring (TTY only) ---
if [ -t 1 ]; then
  C_GREEN=$(tput setaf 2 || true); C_CYAN=$(tput setaf 6 || true)
  C_YELL=$(tput setaf 3 || true);  C_RED=$(tput setaf 1 || true)
  C_BOLD=$(tput bold || true);     C_RESET=$(tput sgr0 || true)
else
  C_GREEN=""; C_CYAN=""; C_YELL=""; C_RED=""; C_BOLD=""; C_RESET=""
fi

msg() { printf '%b\n' "$*"; }
die() { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    die "Run as root or with sudo."
  fi
}

# =====================================================================
# Validation (v2.4: real range checks, not just shape checks)
# =====================================================================

is_domain() { [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; }

valid_ipv4() {
  local ip="$1" o
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for o in "${BASH_REMATCH[@]:1:4}"; do
    # reject leading zeros like 01 (ambiguous octal) and values >255
    [[ "$o" =~ ^0$|^[1-9][0-9]{0,2}$ ]] || return 1
    [ "$o" -le 255 ] || return 1
  done
  return 0
}

valid_cidr4() {
  local net="${1%/*}" pfx="${1##*/}"
  [[ "$1" == */* ]] || return 1
  valid_ipv4 "$net" || return 1
  [[ "$pfx" =~ ^[0-9]{1,2}$ ]] || return 1
  [ "$pfx" -le 32 ]
}

valid_ipv6_addr() {
  # structural check, pure bash: hex groups <=4 digits, at most one '::'
  local a="$1"
  [[ "$a" == *:* ]] || return 1
  [[ "$a" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  [[ "$a" == *:::* ]] && return 1
  # at most one '::'
  local t="${a/::/}"
  [[ "$t" == *::* ]] && return 1
  # no group longer than 4 hex digits
  [[ "$a" =~ (^|:)[0-9A-Fa-f]{5,}(:|$) ]] && return 1
  # group count sanity: with '::' up to 8 groups total, without it exactly 8
  local IFS=':' groups=0 g
  # shellcheck disable=SC2086
  set -- $a
  for g in "$@"; do [ -n "$g" ] && groups=$((groups+1)); done
  if [[ "$a" == *::* ]]; then
    [ "$groups" -le 7 ]
  else
    [ "$groups" -eq 8 ]
  fi
}

valid_cidr6() {
  local net="${1%/*}" pfx="${1##*/}"
  [[ "$1" == */* ]] || return 1
  [[ "$net" == *:* ]] || return 1
  valid_ipv6_addr "$net" || return 1
  [[ "$pfx" =~ ^[0-9]{1,3}$ ]] || return 1
  [ "$pfx" -le 128 ]
}

is_cidr() { valid_cidr4 "$1" || valid_cidr6 "$1"; }

ENTRY_TYPE=""
entry_type() {
  # Sets $ENTRY_TYPE to: domain | ip | ip6 | cidr | invalid.
  # A result variable instead of printing: a $(...) substitution would fork
  # a subshell per input line, which dominates runtime on bulk imports.
  local e="$1"
  if valid_cidr4 "$e" || valid_cidr6 "$e"; then ENTRY_TYPE='cidr'
  elif valid_ipv4 "$e"; then ENTRY_TYPE='ip'
  elif valid_ipv6_addr "$e"; then ENTRY_TYPE='ip6'
  elif is_domain "$e"; then ENTRY_TYPE='domain'
  else ENTRY_TYPE='invalid'
  fi
}

TRIMMED=""
trim_lower() {
  # Pure-bash lowercase + CR strip + whitespace trim. Sets $TRIMMED instead
  # of printing: a $(...) substitution would fork a subshell per input line,
  # which dominates runtime on bulk imports.
  local s="${1,,}"
  s="${s//$'\r'/}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  TRIMMED="$s"
}

# =====================================================================
# Postfix integration: --check / --setup (v2.4: order-aware, rollback)
# =====================================================================

# Results via globals: INT_HASH, INT_CIDR, INT_ORDER_OK, INT_DUPES
inspect_integration() {
  local rr
  rr="$(postconf -h smtpd_recipient_restrictions 2>/dev/null || true)"
  INT_HASH=0; INT_CIDR=0; INT_ORDER_OK=0; INT_DUPES=0

  # NB: grep exits 1 on zero matches; with pipefail that would kill the
  # script under set -e, so the assignments are guarded with || true.
  local hash_count cidr_count
  hash_count="$(grep -o -F "hash:${POSTFIX_FILE}" <<< "$rr" | wc -l)" || true
  cidr_count="$(grep -o -F "cidr:${CIDR_FILE}" <<< "$rr" | wc -l)" || true
  [ "$hash_count" -ge 1 ] && INT_HASH=1
  [ "$cidr_count" -ge 1 ] && INT_CIDR=1
  { [ "$hash_count" -gt 1 ] || [ "$cidr_count" -gt 1 ]; } && INT_DUPES=1

  # Ordering: our maps must appear BEFORE the first check_policy_service
  # (postgrey). Maps placed after it never fire — postgrey answers first.
  if [ "$INT_HASH" -eq 1 ] && [ "$INT_CIDR" -eq 1 ]; then
    if [[ "$rr" == *check_policy_service* ]]; then
      local before="${rr%%check_policy_service*}"
      if [[ "$before" == *"hash:${POSTFIX_FILE}"* ]] && [[ "$before" == *"cidr:${CIDR_FILE}"* ]]; then
        INT_ORDER_OK=1
      fi
    else
      INT_ORDER_OK=1
    fi
  fi
  return 0
}

integration_ok() {
  [ "$INT_HASH" -eq 1 ] && [ "$INT_CIDR" -eq 1 ] && [ "$INT_ORDER_OK" -eq 1 ] && [ "$INT_DUPES" -eq 0 ]
}

do_check() {
  command -v postconf >/dev/null 2>&1 || die "postconf not found — is Postfix installed?"
  inspect_integration
  msg "🔎 ${C_BOLD}Postfix integration status:${C_RESET}"
  if [ "$INT_HASH" -eq 1 ]; then msg "   ✅ hash map present:  $HASH_TOKEN"
  else msg "   ❌ hash map NOT wired (run --setup)"; fi
  if [ "$INT_CIDR" -eq 1 ]; then msg "   ✅ cidr map present:  $CIDR_TOKEN"
  else msg "   ❌ cidr map NOT wired (run --setup)"; fi
  if [ "$INT_HASH" -eq 1 ] && [ "$INT_CIDR" -eq 1 ]; then
    if [ "$INT_ORDER_OK" -eq 1 ]; then
      msg "   ✅ ordering OK: maps act before the greylisting policy service"
    else
      msg "   ❌ ordering WRONG: maps appear AFTER check_policy_service — they never fire (re-run --setup)"
    fi
  fi
  [ "$INT_DUPES" -eq 1 ] && msg "   ⚠️  duplicate check_client_access tokens detected — re-run --setup to clean up"
  msg ""
  msg "   smtpd_recipient_restrictions ="
  postconf -h smtpd_recipient_restrictions | sed 's/,/,\n      /g;s/^/      /'
  # Exit code reflects status so --check is scriptable (post-update checklists).
  if integration_ok; then exit 0; else exit 2; fi
}

do_setup() {
  require_root
  command -v postconf >/dev/null 2>&1 || die "postconf not found — is Postfix installed?"
  local rr new
  rr="$(postconf -h smtpd_recipient_restrictions)"
  [ -n "$rr" ] || die "smtpd_recipient_restrictions is empty — unexpected for MIAB; aborting."

  inspect_integration
  if integration_ok; then
    msg "✅ Already wired correctly. Nothing to do."
    exit 0
  fi

  # Strategy: rebuild the chain — drop ALL existing occurrences of our tokens
  # (handles duplicates and wrong position), then insert both right BEFORE the
  # first check_policy_service (postgrey). A whitelisted client therefore skips
  # greylisting but still passes RBL checks and reject_unlisted_recipient.
  local IFS=',' part t
  local -a parts=() kept=()
  read -ra parts <<< "$rr"
  for part in "${parts[@]}"; do
    t="${part#"${part%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [ -z "$t" ] && continue
    [ "$t" = "$HASH_TOKEN" ] && continue
    [ "$t" = "$CIDR_TOKEN" ] && continue
    kept+=( "$t" )
  done

  local -a rebuilt=()
  local inserted=0
  for t in "${kept[@]}"; do
    if [ "$inserted" -eq 0 ] && [[ "$t" == check_policy_service* ]]; then
      rebuilt+=( "$HASH_TOKEN" "$CIDR_TOKEN" )
      inserted=1
    fi
    rebuilt+=( "$t" )
  done
  if [ "$inserted" -eq 0 ]; then
    msg "⚠️  ${C_YELL}No check_policy_service found in restrictions — appending maps at the end.${C_RESET}"
    msg "   Verify the resulting order manually: earlier reject rules will still win."
    rebuilt+=( "$HASH_TOKEN" "$CIDR_TOKEN" )
  fi
  local out=""
  for t in "${rebuilt[@]}"; do
    if [ -z "$out" ]; then out="$t"; else out="${out}, ${t}"; fi
  done
  new="$out"

  # Ensure map files exist BEFORE reload so Postfix does not fail on a missing map.
  [ -f "$POSTFIX_FILE" ] || { touch "$POSTFIX_FILE"; chmod 644 "$POSTFIX_FILE"; }
  [ -f "${POSTFIX_FILE}.db" ] || postmap "$POSTFIX_FILE"
  [ -f "$CIDR_FILE" ] || { touch "$CIDR_FILE"; chmod 644 "$CIDR_FILE"; }

  msg "🧩 Updating smtpd_recipient_restrictions:"
  msg "   + ${HASH_TOKEN}"
  msg "   + ${CIDR_TOKEN}"
  postconf -e "smtpd_recipient_restrictions = ${new}"

  # v2.4: rollback on failure — never leave a broken main.cf behind
  if ! postfix check; then
    msg "↩️  ${C_RED}postfix check failed — rolling back${C_RESET}"
    postconf -e "smtpd_recipient_restrictions = ${rr}"
    postfix check || true
    log_line "SETUP FAILED (postfix check), rolled back"
    die "Setup aborted; previous configuration restored."
  fi
  if ! postfix reload; then
    msg "↩️  ${C_RED}postfix reload failed — rolling back${C_RESET}"
    postconf -e "smtpd_recipient_restrictions = ${rr}"
    postfix reload || true
    log_line "SETUP FAILED (postfix reload), rolled back"
    die "Setup aborted; previous configuration restored."
  fi

  log_line "SETUP wired (order-corrected): $new"
  msg "✅ ${C_GREEN}Postfix integration complete.${C_RESET}"
  msg "⚠️  ${C_YELL}Note:${C_RESET} MIAB updates may overwrite smtpd_recipient_restrictions — re-run --setup after each update."
  exit 0
}

list_one_file() {
  # Print counters, mtime and entries of a single whitelist file.
  local path="$1" label="$2" count mtime
  msg ""
  if [ ! -f "$path" ]; then
    msg "📄 ${C_BOLD}${label}${C_RESET} — ${path}: ${C_YELL}file does not exist${C_RESET}"
    return 0
  fi
  count="$(grep -cvE '^[[:space:]]*(#|$)' "$path" 2>/dev/null || true)"
  mtime="$(date -r "$path" '+%F %T' 2>/dev/null || echo '?')"
  msg "📄 ${C_BOLD}${label}${C_RESET} — ${path} (${C_CYAN}${count}${C_RESET} entries, modified ${mtime})"
  if [ "$count" -gt 0 ]; then
    grep -vE '^[[:space:]]*(#|$)' "$path" | sed 's/^/   /'
  fi
}

do_list() {
  msg "🔧 add_whitelists.sh v${VERSION} — current whitelist state"
  list_one_file "$POSTFIX_FILE"  "Postfix hash map"
  list_one_file "$CIDR_FILE"     "Postfix cidr map"
  list_one_file "$POSTGREY_FILE" "Postgrey whitelist"
  msg ""
  inspect_integration
  if integration_ok; then
    msg "🔌 Postfix integration: ${C_GREEN}wired correctly${C_RESET} (both maps before the policy service)"
  else
    msg "🔌 Postfix integration: ${C_YELL}NOT correctly wired${C_RESET} — run: sudo add_whitelists.sh --setup"
  fi
  exit 0
}

already_in_file() {
  # v2.4: exact first-field comparison in awk — no user input in regexes.
  local needle="$1" file="$2"
  [ -f "$file" ] || return 1
  awk -v e="$needle" '$1 == e {found=1; exit} END {exit !found}' "$file"
}

remove_from_file() {
  # Remove a validated entry from one whitelist file. Returns 0 if removed.
  # v2.4: exact first-field match via awk + atomic tmp+mv (same filesystem).
  local entry="$1" path="$2" tmp
  [ -f "$path" ] || return 1
  already_in_file "$entry" "$path" || return 1
  backup_if_exists "$path"
  tmp="$(mktemp "${path}.XXXXXX")"
  awk -v e="$entry" '$1 != e' "$path" > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$path"
  return 0
}

do_remove() {
  local raw="$1" entry type rm_pf=0 rm_cidr=0 rm_pg=0
  trim_lower "$raw"; entry="$TRIMMED"
  [ -n "$entry" ] || die "--remove requires a non-empty ENTRY"
  # v2.4: validate BEFORE touching files — regex-looking garbage is refused.
  entry_type "$entry"; type="$ENTRY_TYPE"
  [ "$type" = "invalid" ] && die "Refusing to remove: '$entry' is not a valid domain/IP/CIDR."
  msg "🔧 add_whitelists.sh v${VERSION} — removing: $entry"

  if remove_from_file "$entry" "$POSTFIX_FILE";  then rm_pf=1;   msg "🗑  Removed from Postfix hash: $entry";  log_line "REMOVE Postfix $entry"; fi
  if remove_from_file "$entry" "$CIDR_FILE";     then rm_cidr=1; msg "🗑  Removed from Postfix cidr: $entry";  log_line "REMOVE Postfix-cidr $entry"; fi
  if remove_from_file "$entry" "$POSTGREY_FILE"; then rm_pg=1;   msg "🗑  Removed from Postgrey: $entry";      log_line "REMOVE Postgrey $entry"; fi

  if [ "$rm_pf" -eq 0 ] && [ "$rm_cidr" -eq 0 ] && [ "$rm_pg" -eq 0 ]; then
    msg "ℹ️ Entry not found in any whitelist file: $entry"
    exit 1
  fi

  if [ "$rm_pf" -eq 1 ]; then
    msg "🧰 postmap $POSTFIX_FILE"
    postmap "$POSTFIX_FILE"
  fi
  if [ "$rm_pf" -eq 1 ] || [ "$rm_cidr" -eq 1 ]; then
    msg "🔄 Reloading Postfix"
    postfix reload
  fi
  if [ "$rm_pg" -eq 1 ]; then
    msg "🔄 Reloading Postgrey"
    systemctl reload postgrey 2>/dev/null || systemctl restart postgrey || true
  fi
  msg "✅ ${C_GREEN}Removed.${C_RESET} Postfix=${rm_pf}, Cidr=${rm_cidr}, Postgrey=${rm_pg}"
  exit 0
}

do_verify() {
  local raw="$1" entry hit=0 out
  trim_lower "$raw"; entry="$TRIMMED"
  [ -n "$entry" ] || die "--verify requires a non-empty ENTRY"
  command -v postmap >/dev/null 2>&1 || die "postmap not found — is Postfix installed?"
  msg "🔎 ${C_BOLD}Verify:${C_RESET} $entry"

  # Postfix hash map (queried the same way smtpd does)
  if [ -f "${POSTFIX_FILE}.db" ]; then
    if out="$(postmap -q "$entry" "hash:${POSTFIX_FILE}" 2>/dev/null)"; then
      msg "   ✅ Postfix hash map: matched (${out})"; hit=1
    else
      msg "   ❌ Postfix hash map: no match"
    fi
  else
    msg "   ⚠️  Postfix hash map: ${POSTFIX_FILE}.db missing (run --setup or add an entry first)"
  fi

  # Postfix cidr map: for addresses postmap -q does real CIDR containment;
  # for a CIDR entry itself we check literal presence in the file.
  if [ -f "$CIDR_FILE" ]; then
    if is_cidr "$entry"; then
      if already_in_file "$entry" "$CIDR_FILE"; then
        msg "   ✅ Postfix cidr map: entry present"; hit=1
      else
        msg "   ❌ Postfix cidr map: entry not present"
      fi
    elif out="$(postmap -q "$entry" "cidr:${CIDR_FILE}" 2>/dev/null)"; then
      msg "   ✅ Postfix cidr map: covered by a whitelisted range (${out})"; hit=1
    else
      msg "   ❌ Postfix cidr map: not covered"
    fi
  else
    msg "   ⚠️  Postfix cidr map: $CIDR_FILE missing"
  fi

  # Postgrey (exact entry; postgrey itself also matches subdomains/prefixes)
  if [ -f "$POSTGREY_FILE" ] && already_in_file "$entry" "$POSTGREY_FILE"; then
    msg "   ✅ Postgrey: entry present"
  else
    msg "   ❌ Postgrey: entry not present (note: a parent domain/range may still cover it)"
  fi

  inspect_integration
  if integration_ok; then
    msg "   🔌 Postfix integration: ${C_GREEN}wired correctly${C_RESET}"
  else
    msg "   🔌 Postfix integration: ${C_YELL}NOT correctly wired${C_RESET} — Postfix matches above are inactive until --setup"
  fi
  [ "$hit" -eq 1 ] && exit 0 || exit 1
}

ensure_file() {
  # create parent dir and file if missing
  local path="$1" dir
  dir="$(dirname "$path")"
  if [ ! -d "$dir" ]; then
    msg "📁 ${C_YELL}Creating dir:${C_RESET} $dir"
    if [ "$DRY" -eq 0 ]; then mkdir -p "$dir"; fi
  fi
  if [ ! -f "$path" ]; then
    msg "📝 ${C_YELL}Creating file:${C_RESET} $path"
    if [ "$DRY" -eq 0 ]; then
      touch "$path"
      chmod 644 "$path"
    fi
  fi
}

backup_if_exists() {
  local path="$1"
  if [ -f "$path" ]; then
    msg "🗂  ${C_CYAN}Backup:${C_RESET} ${path}.bak_${BACKUP_DATE}"
    if [ "$DRY" -eq 0 ]; then cp -a "$path" "${path}.bak_${BACKUP_DATE}"; fi
  fi
}

rotate_backups() {
  # Remove backups older than BACKUP_RETENTION_DAYS for a given whitelist file.
  local path="$1" dir base
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  [ "$DRY" -eq 0 ] || return 0
  find "$dir" -maxdepth 1 -name "${base}.bak_*" -mtime "+${BACKUP_RETENTION_DAYS}" -delete 2>/dev/null || true
}

# In-memory caches of existing entries (first token of each line).
# Loaded once before processing, so bulk imports do O(1) hash lookups
# instead of forking a grep/awk per entry per file.
declare -A KNOWN_PF=() KNOWN_CIDR=() KNOWN_PG=()

load_known() {
  # load_known <file> <arrayname>
  local file="$1" key _rest
  local -n _known="$2"
  [ -f "$file" ] || return 0
  while read -r key _rest; do
    [ -z "$key" ] && continue
    case "$key" in \#*) continue ;; esac
    _known["$key"]=1
  done < "$file"
}

add_postfix() {
  local v="$1"
  [ -n "${KNOWN_PF[$v]:-}" ] && return 1
  KNOWN_PF[$v]=1
  [ "$DRY" -eq 0 ] && printf '%s OK\n' "$v" >> "$POSTFIX_FILE"
  return 0
}

add_cidr() {
  local v="$1"
  [ -n "${KNOWN_CIDR[$v]:-}" ] && return 1
  KNOWN_CIDR[$v]=1
  [ "$DRY" -eq 0 ] && printf '%s OK\n' "$v" >> "$CIDR_FILE"
  return 0
}

add_postgrey() {
  local v="$1"
  [ -n "${KNOWN_PG[$v]:-}" ] && return 1
  KNOWN_PG[$v]=1
  [ "$DRY" -eq 0 ] && printf '%s\n' "$v" >> "$POSTGREY_FILE"
  return 0
}

# collectors
ADDED_ALL=()
ADDED_PF=0
ADDED_CIDR=0
ADDED_PG=0
ERRORS=0

apply_entry() {
  # entry is pre-validated in phase 1; type passed in
  local entry="$1" type="$2" touched=0
  case "$type" in
    cidr)
      if add_cidr "$entry"; then ADDED_CIDR=$((ADDED_CIDR+1)); touched=1; log_line "ADD Postfix-cidr $entry"; else log_line "SKIP duplicate (Postfix-cidr) $entry"; fi
      if add_postgrey "$entry"; then ADDED_PG=$((ADDED_PG+1)); touched=1; log_line "ADD Postgrey CIDR $entry"; else log_line "SKIP duplicate (Postgrey) CIDR $entry"; fi
      ;;
    ip6)
      # Bare IPv6 address: the cidr map matches it as a full-length /128
      if add_cidr "$entry"; then ADDED_CIDR=$((ADDED_CIDR+1)); touched=1; log_line "ADD Postfix-cidr IPv6 $entry"; else log_line "SKIP duplicate (Postfix-cidr) IPv6 $entry"; fi
      if add_postgrey "$entry"; then ADDED_PG=$((ADDED_PG+1)); touched=1; log_line "ADD Postgrey IPv6 $entry"; else log_line "SKIP duplicate (Postgrey) IPv6 $entry"; fi
      ;;
    ip)
      if add_postfix "$entry"; then ADDED_PF=$((ADDED_PF+1)); touched=1; log_line "ADD Postfix IP $entry"; else log_line "SKIP duplicate (Postfix) IP $entry"; fi
      if add_postgrey "$entry"; then ADDED_PG=$((ADDED_PG+1)); touched=1; log_line "ADD Postgrey IP $entry"; else log_line "SKIP duplicate (Postgrey) IP $entry"; fi
      ;;
    domain)
      if add_postfix "$entry"; then ADDED_PF=$((ADDED_PF+1)); touched=1; log_line "ADD Postfix domain $entry"; else log_line "SKIP duplicate (Postfix) domain $entry"; fi
      if add_postgrey "$entry"; then ADDED_PG=$((ADDED_PG+1)); touched=1; log_line "ADD Postgrey domain $entry"; else log_line "SKIP duplicate (Postgrey) domain $entry"; fi
      ;;
  esac
  [ "$touched" -eq 1 ] && ADDED_ALL+=( "$entry" )
  return 0
}

# --- arg parsing ---
# Long options first (getopts handles only short ones). Value-taking long
# options (--remove/--verify) consume the following argument. Modifier long
# options (--best-effort) are filtered out before getopts sees them.
ACTION=""
ACTION_ARG=""
BEST_EFFORT=0
EXPECT_VALUE=0
SHORT_ARGS=()
for arg in "$@"; do
  if [ "$EXPECT_VALUE" -eq 1 ]; then
    ACTION_ARG="$arg"; EXPECT_VALUE=0; continue
  fi
  case "$arg" in
    --version)     printf 'add_whitelists.sh v%s\n' "$VERSION"; exit 0 ;;
    --help)        usage ;;
    --setup)       ACTION="setup" ;;
    --check)       ACTION="check" ;;
    --list)        ACTION="list" ;;
    --remove)      ACTION="remove"; EXPECT_VALUE=1 ;;
    --verify)      ACTION="verify"; EXPECT_VALUE=1 ;;
    --best-effort) BEST_EFFORT=1 ;;
    *)             SHORT_ARGS+=( "$arg" ) ;;
  esac
done

DRY=0
LIST_FILE=""
if [ -n "$ACTION" ]; then
  case "$ACTION" in
    setup)  prepare_log; do_setup ;;
    check)  do_check ;;
    list)   do_list ;;
    remove)
      [ -n "$ACTION_ARG" ] || die "--remove requires an ENTRY argument"
      require_root; prepare_log; do_remove "$ACTION_ARG" ;;
    verify)
      [ -n "$ACTION_ARG" ] || die "--verify requires an ENTRY argument"
      do_verify "$ACTION_ARG" ;;
  esac
fi

set -- ${SHORT_ARGS[@]+"${SHORT_ARGS[@]}"}
while getopts ":f:nh" opt; do
  case "$opt" in
    f) LIST_FILE="$OPTARG" ;;
    n) DRY=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
SINGLE_TARGET="${1:-}"

if [ -z "$SINGLE_TARGET" ] && [ -z "$LIST_FILE" ]; then
  usage
fi

# ------------ main ------------
require_root
prepare_log
msg "🔧 add_whitelists.sh v${VERSION} (dry-run: $DRY, best-effort: $BEST_EFFORT)"
[ "$LOG_ENABLED" -eq 1 ] && log_line "START v$VERSION dry=$DRY best_effort=$BEST_EFFORT args: $*"

# -------- Phase 1: collect + validate the whole batch (v2.4) --------
ENTRIES=()
TYPES=()
INVALID=()

collect_entry() {
  local raw="$1" entry type
  trim_lower "$raw"
  entry="$TRIMMED"
  [ -z "$entry" ] && return 0
  [[ "$entry" == \#* ]] && return 0
  entry_type "$entry"; type="$ENTRY_TYPE"
  if [ "$type" = "invalid" ]; then
    INVALID+=( "$entry" )
    ERRORS=$((ERRORS+1))
    log_line "ERROR invalid entry $entry"
  else
    ENTRIES+=( "$entry" )
    TYPES+=( "$type" )
  fi
  return 0
}

if [ -n "$LIST_FILE" ]; then
  [ -f "$LIST_FILE" ] || die "File not found: $LIST_FILE"
  while IFS= read -r line || [ -n "$line" ]; do
    collect_entry "$line"
  done < "$LIST_FILE"
else
  collect_entry "$SINGLE_TARGET"
fi

if [ "${#INVALID[@]}" -gt 0 ]; then
  msg "❌ ${C_RED}Invalid entries (${#INVALID[@]}):${C_RESET}"
  for e in "${INVALID[@]}"; do msg "   ✗ $e"; done
  if [ "$BEST_EFFORT" -eq 0 ]; then
    msg "🛑 ${C_RED}Batch aborted — nothing was applied.${C_RESET} Fix the entries or re-run with --best-effort."
    log_line "ABORT batch: ${#INVALID[@]} invalid entries"
    exit 2
  fi
  msg "⚠️  ${C_YELL}--best-effort: continuing with valid entries only.${C_RESET}"
fi

# -------- Phase 2: backups + apply --------
ensure_file "$POSTFIX_FILE"
ensure_file "$CIDR_FILE"
ensure_file "$POSTGREY_FILE"
backup_if_exists "$POSTFIX_FILE"
backup_if_exists "$CIDR_FILE"
backup_if_exists "$POSTGREY_FILE"
rotate_backups "$POSTFIX_FILE"
rotate_backups "$CIDR_FILE"
rotate_backups "$POSTGREY_FILE"

# One pass over the existing files, then all duplicate checks are in-memory.
load_known "$POSTFIX_FILE"  KNOWN_PF
load_known "$CIDR_FILE"     KNOWN_CIDR
load_known "$POSTGREY_FILE" KNOWN_PG

idx=0
while [ "$idx" -lt "${#ENTRIES[@]}" ]; do
  apply_entry "${ENTRIES[$idx]}" "${TYPES[$idx]}"
  idx=$((idx+1))
done

if [ "$DRY" -eq 0 ]; then
  if [ "$ADDED_PF" -gt 0 ]; then
    msg "🧰 postmap $POSTFIX_FILE"
    postmap "$POSTFIX_FILE"
  fi
  if [ "$ADDED_PF" -gt 0 ] || [ "$ADDED_CIDR" -gt 0 ]; then
    # reload, not restart: does not drop active SMTP sessions; cidr maps are
    # re-read on reload, hash maps via the freshly postmapped .db
    msg "🔄 Reloading Postfix"
    postfix reload
    log_line "RELOAD postfix (hash=$ADDED_PF cidr=$ADDED_CIDR)"
  fi
  if [ "$ADDED_PG" -gt 0 ]; then
    # reload (SIGHUP) makes postgrey re-read its whitelists without dropping
    # state; fall back to restart where the unit has no reload action
    msg "🔄 Reloading Postgrey"
    systemctl reload postgrey 2>/dev/null || systemctl restart postgrey || true
    log_line "RELOAD postgrey (added=$ADDED_PG)"
  fi
  msg "✅ ${C_GREEN}Done.${C_RESET} Added: Postfix=${C_CYAN}${ADDED_PF}${C_RESET}, Cidr=${C_CYAN}${ADDED_CIDR}${C_RESET}, Postgrey=${C_CYAN}${ADDED_PG}${C_RESET}, Errors=${C_CYAN}${ERRORS}${C_RESET}"

  # Safety net: adding Postfix entries is pointless while the maps are not
  # wired (or are misordered) in smtpd_recipient_restrictions — tell the user
  # instead of letting them feed a dead file for months.
  if [ "$ADDED_PF" -gt 0 ] || [ "$ADDED_CIDR" -gt 0 ]; then
    inspect_integration
    if ! integration_ok; then
      msg "⚠️  ${C_YELL}Postfix maps are not correctly wired into smtpd_recipient_restrictions.${C_RESET}"
      msg "   The Postgrey layer works, but the Postfix-level bypass is inactive or misordered."
      msg "   Run: sudo add_whitelists.sh --setup"
    fi
  fi
else
  msg "🔎 Dry-run complete. Would add: Postfix=${ADDED_PF}, Cidr=${ADDED_CIDR}, Postgrey=${ADDED_PG}, Errors=${ERRORS}"
fi

# Summary list of actually added items (deduplicated by logic above)
if [ "${#ADDED_ALL[@]}" -gt 0 ]; then
  msg ""
  msg "📊 ${C_BOLD}Added to whitelist (${#ADDED_ALL[@]} items):${C_RESET}"
  for item in "${ADDED_ALL[@]}"; do
    if is_cidr "$item"; then
      printf '   🧩 %s%s%s\n' "$C_YELL" "$item" "$C_RESET"
    elif valid_ipv4 "$item" || valid_ipv6_addr "$item"; then
      printf '   🌐 %s%s%s\n' "$C_CYAN" "$item" "$C_RESET"
    else
      printf '   🏷  %s%s%s\n' "$C_GREEN" "$item" "$C_RESET"
    fi
  done
else
  msg "ℹ️ No new entries were added."
fi

exit_code=0
[ "$ERRORS" -gt 0 ] && exit_code=2
[ "$LOG_ENABLED" -eq 1 ] && log_line "END pf=$ADDED_PF cidr=$ADDED_CIDR pg=$ADDED_PG errors=$ERRORS exit=$exit_code"
exit "$exit_code"
