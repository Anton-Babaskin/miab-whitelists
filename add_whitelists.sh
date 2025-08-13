#!/usr/bin/env bash
# add_whitelists.sh - Add domains/IPs to Postfix and Postgrey whitelists
# Author: Anton Babaskin

set -Eeuo pipefail

POSTFIX_FILE="/etc/postfix/client_whitelist"
POSTGREY_FILE="/etc/postgrey/whitelist_clients.local"
BACKUP_DATE="$(date +%F_%H%M%S)"

usage() {
  cat <<EOF
Usage:
  $0 [-n] <domain-or-ip>
  $0 [-n] -f <file_with_entries>

Options:
  -f FILE   File with entries (one per line, empty lines and #comments ignored)
  -n        Dry-run mode (no changes applied)
  -h        Show this help message

Examples:
  $0 example.com
  $0 203.0.113.7
  $0 -f whitelist.txt
  $0 -n -f whitelist.txt
EOF
  exit 1
}

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
shift $((OPTIND -1))

SINGLE_TARGET="${1:-}"

if [[ -z "$SINGLE_TARGET" && -z "$LIST_FILE" ]]; then
  usage
fi

msg() { printf '%b\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "Run as root or with sudo."
  fi
}

ensure_file() {
  local path="$1"
  local dir
  dir="$(dirname "$path")"
  if [[ ! -d "$dir" ]]; then
    msg "📁 Creating directory: $dir"
    [[ $DRY -eq 0 ]] && mkdir -p "$dir"
  fi
  if [[ ! -f "$path" ]]; then
    msg "📝 Creating file: $path"
    [[ $DRY -eq 0 ]] && touch "$path"
    [[ $DRY -eq 0 ]] && chmod 644 "$path"
  fi
}

backup_if_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    msg "🗂  Backup: ${path}.bak_${BACKUP_DATE}"
    [[ $DRY -eq 0 ]] && cp -a "$path" "${path}.bak_${BACKUP_DATE}"
  fi
}

is_domain() {
  local s="$1"
  [[ "$s" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]
}

is_ipv4() {
  local s="$1"
  [[ "$s" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_cidr() {
  local s="$1"
  [[ "$s" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]
}

already_in_file() {
  local needle="$1" file="$2"
  grep -qE -- "^${needle//./\\.}([[:space:]]|$)" "$file"
}

add_postfix() {
  local v="$1"
  if already_in_file "$v" "$POSTFIX_FILE"; then
    msg "ℹ️  Already in Postfix: $v"
    return 1
  fi
  msg "➕ Adding to Postfix: $v OK"
  [[ $DRY -eq 0 ]] && echo "$v OK" >> "$POSTFIX_FILE"
  return 0
}

add_postgrey() {
  local v="$1"
  if already_in_file "$v" "$POSTGREY_FILE"; then
    msg "ℹ️  Already in Postgrey: $v"
    return 1
  fi
  msg "➕ Adding to Postgrey: $v"
  [[ $DRY -eq 0 ]] && echo "$v" >> "$POSTGREY_FILE"
  return 0
}

require_root
msg "🔧 Dry-run: $DRY"

ensure_file "$POSTFIX_FILE"
ensure_file "$POSTGREY_FILE"
backup_if_exists "$POSTFIX_FILE"
backup_if_exists "$POSTGREY_FILE"

CHANGED_POSTFIX=0
CHANGED_POSTGREY=0
ERRORS=0

process_entry() {
  local raw="$1"
  local entry
  entry="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | xargs)"
  [[ -z "$entry" ]] && return 0
  [[ "$entry" =~ ^# ]] && return 0

  if is_cidr "$entry"; then
    msg "⚠️  CIDR '$entry' not supported in hash map. Use a CIDR map instead."
    return 0
  elif is_ipv4 "$entry"; then
    add_postfix "$entry" && CHANGED_POSTFIX=1 || true
  elif is_domain "$entry"; then
    add_postfix "$entry" && CHANGED_POSTFIX=1 || true
    add_postgrey "$entry" && CHANGED_POSTGREY=1 || true
  else
    msg "❌ Invalid entry: $entry"
    ERRORS=$((ERRORS+1))
    return 1
  fi
}

if [[ -n "$LIST_FILE" ]]; then
  [[ -f "$LIST_FILE" ]] || die "File not found: $LIST_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    process_entry "$line" || true
  done < "$LIST_FILE"
else
  process_entry "$SINGLE_TARGET" || true
fi

if [[ $DRY -eq 0 ]]; then
  if [[ $CHANGED_POSTFIX -eq 1 ]]; then
    msg "🧰 postmap $POSTFIX_FILE"
    postmap "$POSTFIX_FILE"
    msg "🔄 Restarting Postfix"
    systemctl restart postfix
  fi
  if [[ $CHANGED_POSTGREY -eq 1 ]]; then
    msg "🔄 Restarting Postgrey"
    systemctl restart postgrey || true
  fi
  msg "✅ Done. Changes: Postfix=${CHANGED_POSTFIX}, Postgrey=${CHANGED_POSTGREY}, Errors=${ERRORS}"
else
  msg "🔎 Dry-run complete. Would change: Postfix=${CHANGED_POSTFIX}, Postgrey=${CHANGED_POSTGREY}, Errors=${ERRORS}"
fi
