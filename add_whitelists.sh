#!/usr/bin/env bash
# add_whitelists.sh — add domains/IPs/CIDRs to Postfix + Postgrey whitelists with logging
#
# Routing:
#   Domain     → Postfix hash (entry OK) + Postgrey (entry)
#   IP         → Postfix hash (entry OK) + Postgrey (entry)
#   CIDR v4/v6 → Postfix cidr-map (entry OK) + Postgrey (entry)
#
# Usage:
#   ./add_whitelists.sh example.com
#   ./add_whitelists.sh 1.2.3.4
#   ./add_whitelists.sh 198.51.100.0/24
#   ./add_whitelists.sh 2001:db8::/32
#   ./add_whitelists.sh -f whitelists.txt
#   ./add_whitelists.sh -n -f whitelists.txt   # dry-run
#   ./add_whitelists.sh --setup                # wire maps into Postfix restrictions
#   ./add_whitelists.sh --check                # verify Postfix integration status
#   ./add_whitelists.sh --version

set -Eeuo pipefail

VERSION="2.1"

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
  local ts user msg
  ts="$(date '+%F %T')"
  user="${SUDO_USER:-${USER:-root}}"
  msg="$*"
  if [ "$LOG_ENABLED" -eq 1 ]; then
    printf '%s [%s] %s\n' "$ts" "$user" "$msg" >> "$LOG_FILE" || true
  fi
}

usage() {
  cat <<'EOF'
Usage:
  add_whitelists.sh [-n] <domain-or-ip-or-cidr>
  add_whitelists.sh [-n] -f <file_with_entries>
  add_whitelists.sh --setup     Wire whitelist maps into Postfix (idempotent)
  add_whitelists.sh --check     Show Postfix integration status
  add_whitelists.sh --version   Show script version

Options:
  -f FILE      File with entries (one per line; empty lines and #comments ignored)
  -n           Dry-run (no changes applied)
  -h           Show this help

Routing:
  Domain     -> Postfix hash + Postgrey
  IP         -> Postfix hash + Postgrey
  CIDR v4/v6 -> Postfix cidr-map + Postgrey

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

# --- Postfix integration (--setup / --check) ---
integration_status() {
  # Prints "<hash> <cidr>" where each flag is 1 if the map is wired in.
  # Matched on "hash:<path>" / "cidr:<path>" only, so detection survives
  # whitespace differences around check_client_access.
  local rr h=0 c=0
  rr="$(postconf -h smtpd_recipient_restrictions 2>/dev/null || true)"
  [[ "$rr" == *"hash:${POSTFIX_FILE}"* ]] && h=1
  [[ "$rr" == *"cidr:${CIDR_FILE}"* ]] && c=1
  printf '%d %d' "$h" "$c"
}

do_check() {
  command -v postconf >/dev/null 2>&1 || die "postconf not found — is Postfix installed?"
  local st h c
  st="$(integration_status)"
  h="${st%% *}"; c="${st##* }"
  msg "🔎 ${C_BOLD}Postfix integration status:${C_RESET}"
  if [ "$h" -eq 1 ]; then msg "   ✅ hash map wired:  $HASH_TOKEN"
  else msg "   ❌ hash map NOT wired (run --setup)"; fi
  if [ "$c" -eq 1 ]; then msg "   ✅ cidr map wired:  $CIDR_TOKEN"
  else msg "   ❌ cidr map NOT wired (run --setup)"; fi
  msg ""
  msg "   smtpd_recipient_restrictions ="
  postconf -h smtpd_recipient_restrictions | sed 's/,/,\n      /g;s/^/      /'
  # Exit code reflects status so --check is scriptable (post-update checklists).
  [ "$st" = "1 1" ] && exit 0 || exit 2
}

do_setup() {
  require_root
  command -v postconf >/dev/null 2>&1 || die "postconf not found — is Postfix installed?"
  local rr new st h c
  rr="$(postconf -h smtpd_recipient_restrictions)"
  [ -n "$rr" ] || die "smtpd_recipient_restrictions is empty — unexpected for MIAB; aborting."

  st="$(integration_status)"
  h="${st%% *}"; c="${st##* }"
  if [ "$h" -eq 1 ] && [ "$c" -eq 1 ]; then
    msg "✅ Already wired. Nothing to do."
    exit 0
  fi

  # Our tokens go right BEFORE the first check_policy_service (postgrey), so a
  # whitelisted client skips greylisting but still passes RBL checks and
  # reject_unlisted_recipient (cannot send to nonexistent mailboxes).
  local insert=""
  [ "$h" -eq 0 ] && insert="${HASH_TOKEN}"
  if [ "$c" -eq 0 ]; then
    if [ -n "$insert" ]; then insert="${insert}, ${CIDR_TOKEN}"; else insert="${CIDR_TOKEN}"; fi
  fi

  if [[ "$rr" == *"check_policy_service"* ]]; then
    new="${rr/check_policy_service/${insert}, check_policy_service}"
  else
    msg "⚠️  ${C_YELL}No check_policy_service found in restrictions — appending maps at the end.${C_RESET}"
    msg "   Verify the resulting order manually: earlier reject rules will still win."
    new="${rr}, ${insert}"
  fi

  # Ensure map files exist BEFORE reload so Postfix does not fail on a missing map.
  [ -f "$POSTFIX_FILE" ] || { touch "$POSTFIX_FILE"; chmod 644 "$POSTFIX_FILE"; }
  [ -f "${POSTFIX_FILE}.db" ] || postmap "$POSTFIX_FILE"
  [ -f "$CIDR_FILE" ] || { touch "$CIDR_FILE"; chmod 644 "$CIDR_FILE"; }

  msg "🧩 Wiring into smtpd_recipient_restrictions:"
  msg "   + ${insert}"
  postconf -e "smtpd_recipient_restrictions = ${new}"

  postfix check || die "postfix check failed — review main.cf"
  postfix reload
  log_line "SETUP wired: $insert"
  msg "✅ ${C_GREEN}Postfix integration complete.${C_RESET}"
  msg "⚠️  ${C_YELL}Note:${C_RESET} MIAB updates may overwrite smtpd_recipient_restrictions — re-run --setup after each update."
  exit 0
}

# --- arg parsing ---
# Handle long options first (getopts handles only short ones).
for arg in "$@"; do
  case "$arg" in
    --version) printf 'add_whitelists.sh v%s\n' "$VERSION"; exit 0 ;;
    --help)    usage ;;
    --setup)   prepare_log; do_setup ;;
    --check)   do_check ;;
  esac
done

DRY=0
LIST_FILE=""
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

is_domain() { [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; }
is_ipv4()   { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
is_cidr4()  { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; }
is_cidr6()  { [[ "$1" == *:* ]] && [[ "$1" =~ ^[0-9A-Fa-f:]+/[0-9]{1,3}$ ]]; }
is_cidr()   { is_cidr4 "$1" || is_cidr6 "$1"; }

already_in_file() {
  # match full token at start or before whitespace
  local needle="$1" file="$2"
  [ -f "$file" ] || return 1
  local esc="${needle//./\\.}"
  esc="${esc//\//\\/}"
  grep -qE -- "^${esc}([[:space:]]|$)" "$file"
}

add_postfix() {
  local v="$1"
  if already_in_file "$v" "$POSTFIX_FILE"; then
    return 1
  fi
  [ "$DRY" -eq 0 ] && printf '%s OK\n' "$v" >> "$POSTFIX_FILE"
  return 0
}

add_cidr() {
  local v="$1"
  if already_in_file "$v" "$CIDR_FILE"; then
    return 1
  fi
  [ "$DRY" -eq 0 ] && printf '%s OK\n' "$v" >> "$CIDR_FILE"
  return 0
}

add_postgrey() {
  local v="$1"
  if already_in_file "$v" "$POSTGREY_FILE"; then
    return 1
  fi
  [ "$DRY" -eq 0 ] && printf '%s\n' "$v" >> "$POSTGREY_FILE"
  return 0
}

# collectors
ADDED_ALL=()
ADDED_PF=0
ADDED_CIDR=0
ADDED_PG=0
ERRORS=0

trim_lower() {
  # sed-based trim: xargs chokes on quotes/apostrophes in input; also strip CR
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed 's/\r$//;s/^[[:space:]]*//;s/[[:space:]]*$//'
}

process_entry() {
  local raw="$1" entry
  entry="$(trim_lower "$raw")"
  [ -z "$entry" ] && return 0
  [[ "$entry" =~ ^# ]] && return 0

  local touched=0
  if is_cidr "$entry"; then
    if add_cidr "$entry"; then
      ADDED_CIDR=$((ADDED_CIDR+1)); touched=1; log_line "ADD Postfix-cidr $entry"
    else
      log_line "SKIP duplicate (Postfix-cidr) $entry"
    fi
    if add_postgrey "$entry"; then
      ADDED_PG=$((ADDED_PG+1)); touched=1; log_line "ADD Postgrey CIDR $entry"
    else
      log_line "SKIP duplicate (Postgrey) CIDR $entry"
    fi
  elif is_ipv4 "$entry"; then
    if add_postfix "$entry"; then ADDED_PF=$((ADDED_PF+1)); touched=1; log_line "ADD Postfix IP $entry"; else log_line "SKIP duplicate (Postfix) IP $entry"; fi
    if add_postgrey "$entry"; then ADDED_PG=$((ADDED_PG+1)); touched=1; log_line "ADD Postgrey IP $entry"; else log_line "SKIP duplicate (Postgrey) IP $entry"; fi
  elif is_domain "$entry"; then
    if add_postfix "$entry"; then ADDED_PF=$((ADDED_PF+1)); touched=1; log_line "ADD Postfix domain $entry"; else log_line "SKIP duplicate (Postfix) domain $entry"; fi
    if add_postgrey "$entry"; then ADDED_PG=$((ADDED_PG+1)); touched=1; log_line "ADD Postgrey domain $entry"; else log_line "SKIP duplicate (Postgrey) domain $entry"; fi
  else
    msg "❌ ${C_RED}Invalid entry:${C_RESET} $entry"
    ERRORS=$((ERRORS+1))
    log_line "ERROR invalid entry $entry"
    return 1
  fi
  [ "$touched" -eq 1 ] && ADDED_ALL+=( "$entry" )
  return 0
}

# ------------ main ------------
require_root
prepare_log
msg "🔧 add_whitelists.sh v${VERSION} (dry-run: $DRY)"
[ "$LOG_ENABLED" -eq 1 ] && log_line "START v$VERSION dry=$DRY args: $*"

ensure_file "$POSTFIX_FILE"
ensure_file "$CIDR_FILE"
ensure_file "$POSTGREY_FILE"
backup_if_exists "$POSTFIX_FILE"
backup_if_exists "$CIDR_FILE"
backup_if_exists "$POSTGREY_FILE"
rotate_backups "$POSTFIX_FILE"
rotate_backups "$CIDR_FILE"
rotate_backups "$POSTGREY_FILE"

if [ -n "$LIST_FILE" ]; then
  [ -f "$LIST_FILE" ] || die "File not found: $LIST_FILE"
  while IFS= read -r line || [ -n "$line" ]; do
    process_entry "$line" || true
  done < "$LIST_FILE"
else
  process_entry "$SINGLE_TARGET" || true
fi

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
    msg "🔄 Restarting Postgrey"; systemctl restart postgrey || true
    log_line "RESTART postgrey (added=$ADDED_PG)"
  fi
  msg "✅ ${C_GREEN}Done.${C_RESET} Added: Postfix=${C_CYAN}${ADDED_PF}${C_RESET}, Cidr=${C_CYAN}${ADDED_CIDR}${C_RESET}, Postgrey=${C_CYAN}${ADDED_PG}${C_RESET}, Errors=${C_CYAN}${ERRORS}${C_RESET}"

  # Safety net: adding Postfix entries is pointless while the maps are not
  # wired into smtpd_recipient_restrictions — tell the user instead of letting
  # them feed a dead file for months.
  if [ "$ADDED_PF" -gt 0 ] || [ "$ADDED_CIDR" -gt 0 ]; then
    ST="$(integration_status)"
    if [ "$ST" != "1 1" ]; then
      msg "⚠️  ${C_YELL}Postfix maps are not wired into smtpd_recipient_restrictions.${C_RESET}"
      msg "   Postgrey whitelisting works, but Postfix-level bypass is inactive."
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
    elif is_ipv4 "$item"; then
      printf '   🌐 %s%s%s\n' "$C_CYAN" "$item" "$C_RESET"
    else
      printf '   🏷  %s%s%s\n' "$C_GREEN" "$item" "$C_RESET"
    fi
  done
else
  msg "ℹ️ No new entries were added."
fi

[ "$LOG_ENABLED" -eq 1 ] && log_line "END pf=$ADDED_PF cidr=$ADDED_CIDR pg=$ADDED_PG errors=$ERRORS"
exit 0
