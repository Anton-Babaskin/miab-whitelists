#!/usr/bin/env bash
# add_whitelists.sh — add one or many domains/IPs to Postfix + Postgrey
# Usage:
#   ./add_whitelists.sh example.com
#   ./add_whitelists.sh -f whitelists.txt
#   ./add_whitelists.sh -n -f whitelists.txt   # dry-run

set -Eeuo pipefail

POSTFIX_FILE="/etc/postfix/client_whitelist"
POSTGREY_FILE="/etc/postgrey/whitelist_clients.local"
BACKUP_DATE="$(date +%F_%H%M%S)"

usage() {
  cat <<'EOF'
Usage:
  add_whitelists.sh [-n] <domain-or-ip>
  add_whitelists.sh [-n] -f <file_with_entries>

Options:
  -f FILE   File with entries (one per line; empty lines and #comments ignored)
  -n        Dry-run (no changes applied)
  -h        Show this help
EOF
  exit 1
}

# --- light coloring (TTY only) ---
if [ -t 1 ]; then
  C_GREEN=$(tput setaf 2 || true); C_CYAN=$(tput setaf 6 || true)
  C_YELL=$(tput setaf 3 || true);   C_RED=$(tput setaf 1 || true)
  C_BOLD=$(tput bold || true);      C_RESET=$(tput sgr0 || true)
else
  C_GREEN=""; C_CYAN=""; C_YELL=""; C_RED=""; C_BOLD=""; C_RESET=""
fi

msg() { printf '%b\n' "$*"; }
die() { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

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

[ -z "$SINGLE_TARGET" ] && [ -z "$LIST_FILE" ] && usage

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    die "Run as root or with sudo."
  fi
}

ensure_file() {
  # create parent dir and file if missing
  local path="$1" dir
  dir="$(dirname "$path")"
  if [ ! -d "$dir" ]; then
    msg "📁 ${C_YELL}Creating dir:${C_RESET} $dir"
    [ "$DRY" -eq 0 ] && mkdir -p "$dir"
  fi
  if [ ! -f "$path" ]; then
    msg "📝 ${C_YELL}Creating file:${C_RESET} $path"
    [ "$DRY" -eq 0 ] && touch "$path" && chmod 644 "$path"
  fi
}

backup_if_exists() {
  local path="$1"
  if [ -f "$path" ]; then
    msg "🗂  ${C_CYAN}Backup:${C_RESET} ${path}.bak_${BACKUP_DATE}"
    [ "$DRY" -eq 0 ] && cp -a "$path" "${path}.bak_${BACKUP_DATE}"
  fi
}

is_domain() { [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; }
is_ipv4()   { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
is_cidr()   { [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; }

already_in_file() {
  # match full token at start or before whitespace
  local needle="$1" file="$2"
  grep -qE -- "^${needle//./\\.}([[:space:]]|$)" "$file"
}

add_postfix() {
  local v="$1"
  if already_in_file "$v" "$POSTFIX_FILE"; then
    return 1
  fi
  [ "$DRY" -eq 0 ] && printf '%s OK\n' "$v" >> "$POSTFIX_FILE"
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
ADDED_PG=0
ERRORS=0

process_entry() {
  local raw="$1" entry
  # trim + lower
  entry="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | xargs)"
  [ -z "$entry" ] && return 0
  [[ "$entry" =~ ^# ]] && return 0

  if is_cidr "$entry"; then
    msg "⚠️  ${C_YELL}CIDR not supported in hash map:${C_RESET} $entry"
    return 0
  elif is_ipv4 "$entry"; then
    if add_postfix "$entry"; then
      ADDED_PF=$((ADDED_PF+1)); ADDED_ALL+=( "$entry" )
    fi
  elif is_domain "$entry"; then
    local touched=0
    if add_postfix "$entry"; then ADDED_PF=$((ADDED_PF+1)); touched=1; fi
    if add_postgrey "$entry"; then ADDED_PG=$((ADDED_PG+1)); touched=1; fi
    [ "$touched" -eq 1 ] && ADDED_ALL+=( "$entry" )
  else
    msg "❌ ${C_RED}Invalid entry:${C_RESET} $entry"
    ERRORS=$((ERRORS+1))
    return 1
  fi
}

# ------------ main ------------
require_root
msg "🔧 Dry-run: $DRY"

ensure_file "$POSTFIX_FILE"
ensure_file "$POSTGREY_FILE"
backup_if_exists "$POSTFIX_FILE"
backup_if_exists "$POSTGREY_FILE"

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
    msg "🔄 Restarting Postfix";  systemctl restart postfix
  fi
  if [ "$ADDED_PG" -gt 0 ]; then
    msg "🔄 Restarting Postgrey"; systemctl restart postgrey || true
  fi
  msg "✅ ${C_GREEN}Done.${C_RESET} Changes: Postfix=${C_CYAN}${ADDED_PF}${C_RESET}, Postgrey=${C_CYAN}${ADDED_PG}${C_RESET}, Errors=${C_CYAN}${ERRORS}${C_RESET}"
else
  msg "🔎 Dry-run complete. Would change: Postfix=${ADDED_PF}, Postgrey=${ADDED_PG}, Errors=${ERRORS}"
fi

# Summary list of actually added items (deduplicated by logic above)
if [ "${#ADDED_ALL[@]}" -gt 0 ]; then
  msg ""
  msg "📊 ${C_BOLD}Added to whitelist (${#ADDED_ALL[@]} items):${C_RESET}"
  for item in "${ADDED_ALL[@]}"; do
    if is_ipv4 "$item"; then
      printf '   🌐 %s%s%s\n' "$C_CYAN" "$item" "$C_RESET"
    else
      printf '   🏷  %s%s%s\n' "$C_GREEN" "$item" "$C_RESET"
    fi
  done
else
  msg "ℹ️ No new entries were added."
fi
