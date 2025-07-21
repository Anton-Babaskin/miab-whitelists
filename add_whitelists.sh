#!/bin/bash
set -e  # Exit on any error

# --- FLAG PARSING AND INPUT VALIDATION ---
usage() {
  cat <<EOF
Usage: $0 [-h] [-n] [-f FILE] <domain-or-IP>
  -h        Show this help and exit
  -n        Dry run (no changes applied)
  -f FILE   Path to whitelist file with entries (default: ./whitelist.txt)
EOF
  exit 1
}

DRY_RUN=0
WHITELIST_FILE="./whitelist.txt"
while getopts "hnf:" opt; do
  case $opt in
    h) usage ;;
    n) DRY_RUN=1 ;;
    f) WHITELIST_FILE="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND -1))

TARGET="$1"
if [[ -z "$TARGET" ]]; then
  echo "❌ Missing target. Use -h for help."
  exit 1
fi

# Validate domain or IP/CIDR format
if ! [[ "$TARGET" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}(/[0-9]{1,2})?$ ]] \
    && ! [[ "$TARGET" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]{1,2})?$ ]]; then
  echo "❌ Invalid domain or IP/CIDR: $TARGET"
  exit 1
fi

echo "🔧 Dry run mode: $DRY_RUN"
echo "📋 Whitelist file: $WHITELIST_FILE"
echo "🎯 Target: $TARGET"
# --- /FLAG PARSING AND INPUT VALIDATION ---

POSTFIX_FILE="/etc/postfix/client_whitelist"
POSTGREY_FILE="/etc/postgrey/whitelist_clients.local"

# --- CREATE BACKUPS ---
if [[ $DRY_RUN -eq 0 ]]; then
  cp "$POSTFIX_FILE" "${POSTFIX_FILE}.bak_$(date +%F_%T)"
  cp "$POSTGREY_FILE" "${POSTGREY_FILE}.bak_$(date +%F_%T)"
fi

# --- ROTATE OLD BACKUPS (OLDER THAN 30 DAYS) ---
if [[ $DRY_RUN -eq 0 ]]; then
  find /etc/postfix -name "client_whitelist.bak_*" -mtime +30 -delete
fi

# --- ADD TO POSTFIX WHITELIST ---
if ! grep -qE "^${TARGET//./\\.}($|[[:space:]])" "$POSTFIX_FILE"; then
  if [[ $DRY_RUN -eq 0 ]]; then
    echo "$TARGET OK" >> "$POSTFIX_FILE"
  fi
  echo "✅ Added to Postfix whitelist"
else
  echo "ℹ️ $TARGET is already in Postfix whitelist"
fi

# --- ADD TO POSTGREY WHITELIST ---
if ! grep -qE "^${TARGET//./\\.}($|[[:space:]])" "$POSTGREY_FILE"; then
  if [[ $DRY_RUN -eq 0 ]]; then
    echo "$TARGET" >> "$POSTGREY_FILE"
  fi
  echo "✅ Added to Postgrey whitelist"
else
  echo "ℹ️ $TARGET is already in Postgrey whitelist"
fi

# --- APPLY CHANGES ---
if [[ $DRY_RUN -eq 0 ]]; then
  postmap "$POSTFIX_FILE"
  systemctl restart postfix
  systemctl restart postgrey
  echo "🎉 Done!"
else
  echo "🔎 Dry run complete. No changes were made."
fi
