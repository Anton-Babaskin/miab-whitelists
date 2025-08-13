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
  [[ "$s" =~ ^([0-9]{1,3}]()]()
