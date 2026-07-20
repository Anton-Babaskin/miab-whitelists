#!/usr/bin/env bash
# sync_whitelists.sh — keep a server's whitelists in sync with a git repository.
#
# Designed for fleets: you edit the whitelist in one (private) git repo,
# every server runs this script on a systemd timer and converges on its own:
#   1. git pull --ff-only in the whitelist repo
#   2. add_whitelists.sh -f <whitelist file>   (idempotent, fast)
#   3. add_whitelists.sh --check; if the Postfix maps got unwired
#      (e.g. a MIAB update rewrote main.cf) -> automatic --setup
#   4. on any failure: syslog + optional e-mail alert
#
# Usage:
#   sudo sync_whitelists.sh                  # sync using /etc/miab-whitelists/sync.conf
#   sudo sync_whitelists.sh -c FILE          # alternate config
#   sudo sync_whitelists.sh --install        # write sample config + systemd timer
#   sync_whitelists.sh --version

set -Eeuo pipefail

VERSION="1.0"

CONFIG_FILE="/etc/miab-whitelists/sync.conf"
UNIT_NAME="miab-whitelist-sync"

usage() {
  cat <<'EOF'
Usage:
  sync_whitelists.sh [-c CONFIG]   Run a sync cycle (default config: /etc/miab-whitelists/sync.conf)
  sync_whitelists.sh --install     Create sample config and enable a daily systemd timer
  sync_whitelists.sh --version     Show version
  sync_whitelists.sh -h            Show this help

Config file (shell syntax, sourced as root):
  REPO_DIR="/opt/corporate-whitelist"   # git repo with the whitelist (required)
  WHITELIST_FILE="whitelist.txt"        # path inside the repo (default: whitelist.txt)
  ADD_SCRIPT=""                         # add_whitelists.sh location ("" = auto-detect)
  AUTO_SETUP=1                          # re-run --setup if maps got unwired (1/0)
  ALERT_EMAIL=""                        # e-mail for failure alerts ("" = syslog only)
EOF
  exit 1
}

msg() { printf '%b\n' "$*"; }
die() { alert "sync failed: $*"; printf 'ERROR: %s\n' "$*" >&2; exit 1; }

alert() {
  local text="$1"
  logger -t "$UNIT_NAME" -- "$text" 2>/dev/null || true
  if [ -n "${ALERT_EMAIL:-}" ] && command -v mail >/dev/null 2>&1; then
    printf '%s\n\nHost: %s\nTime: %s\n' "$text" "$(hostname -f 2>/dev/null || hostname)" "$(date '+%F %T')" \
      | mail -s "[$UNIT_NAME] $(hostname): whitelist sync alert" "$ALERT_EMAIL" || true
  fi
}

require_root() {
  [ "${EUID:-$(id -u)}" -eq 0 ] || { printf 'ERROR: Run as root or with sudo.\n' >&2; exit 1; }
}

do_install() {
  require_root
  mkdir -p "$(dirname "$CONFIG_FILE")"
  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<'EOF'
# miab-whitelists sync configuration (sourced by sync_whitelists.sh as root)

# Git repository containing your whitelist (clone it first, e.g. to /opt).
REPO_DIR=""

# Whitelist file inside the repo (entries for add_whitelists.sh -f).
WHITELIST_FILE="whitelist.txt"

# Path to add_whitelists.sh. Empty = auto-detect (PATH, then next to this script).
ADD_SCRIPT=""

# Re-run add_whitelists.sh --setup automatically when the Postfix maps are
# no longer wired in (typically after a Mail-in-a-Box update). 1 = yes.
AUTO_SETUP=1

# Where to send failure alerts. Empty = syslog only.
ALERT_EMAIL=""
EOF
    chmod 600 "$CONFIG_FILE"
    msg "📝 Sample config written: $CONFIG_FILE  — edit REPO_DIR before the first run."
  else
    msg "ℹ️ Config already exists: $CONFIG_FILE"
  fi

  local self
  self="$(readlink -f "$0")"
  if [ "$self" != "/usr/local/bin/sync_whitelists.sh" ]; then
    install -m 0755 "$self" /usr/local/bin/sync_whitelists.sh
    msg "📦 Installed: /usr/local/bin/sync_whitelists.sh"
  fi

  cat > "/etc/systemd/system/${UNIT_NAME}.service" <<EOF
[Unit]
Description=Sync MIAB whitelists from git
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync_whitelists.sh
EOF

  cat > "/etc/systemd/system/${UNIT_NAME}.timer" <<EOF
[Unit]
Description=Daily MIAB whitelist sync

[Timer]
OnCalendar=*-*-* 06:30:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now "${UNIT_NAME}.timer"
  msg "⏰ Timer enabled: ${UNIT_NAME}.timer (daily 06:30 ± 30m, catches up after downtime)"
  msg "   Next: edit $CONFIG_FILE, then test with: sudo sync_whitelists.sh"
  exit 0
}

# --- arg parsing ---
for arg in "$@"; do
  case "$arg" in
    --version) printf 'sync_whitelists.sh v%s\n' "$VERSION"; exit 0 ;;
    --help)    usage ;;
    --install) do_install ;;
  esac
done
while getopts ":c:h" opt; do
  case "$opt" in
    c) CONFIG_FILE="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# --- sync cycle ---
require_root
[ -f "$CONFIG_FILE" ] || { printf 'ERROR: Config not found: %s (run --install first)\n' "$CONFIG_FILE" >&2; exit 1; }

REPO_DIR=""
WHITELIST_FILE="whitelist.txt"
ADD_SCRIPT=""
AUTO_SETUP=1
ALERT_EMAIL=""
# shellcheck source=/dev/null
. "$CONFIG_FILE"

[ -n "$REPO_DIR" ]        || die "REPO_DIR is not set in $CONFIG_FILE"
[ -d "$REPO_DIR/.git" ]   || die "not a git repository: $REPO_DIR"

if [ -z "$ADD_SCRIPT" ]; then
  if command -v add_whitelists.sh >/dev/null 2>&1; then
    ADD_SCRIPT="$(command -v add_whitelists.sh)"
  elif [ -x "$(dirname "$(readlink -f "$0")")/add_whitelists.sh" ]; then
    ADD_SCRIPT="$(dirname "$(readlink -f "$0")")/add_whitelists.sh"
  else
    die "add_whitelists.sh not found (set ADD_SCRIPT in $CONFIG_FILE)"
  fi
fi
[ -x "$ADD_SCRIPT" ] || die "ADD_SCRIPT is not executable: $ADD_SCRIPT"

msg "🔄 sync_whitelists.sh v${VERSION} — repo: $REPO_DIR"

old_head="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo none)"
git -C "$REPO_DIR" pull --ff-only --quiet || die "git pull failed in $REPO_DIR"
new_head="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo none)"
if [ "$old_head" != "$new_head" ]; then
  msg "🆕 Repo updated: ${old_head:0:9} -> ${new_head:0:9}"
else
  msg "ℹ️ Repo unchanged (still applying — idempotent and cheap)."
fi

LIST_PATH="$REPO_DIR/$WHITELIST_FILE"
[ -f "$LIST_PATH" ] || die "whitelist file not found: $LIST_PATH"

"$ADD_SCRIPT" -f "$LIST_PATH" || die "add_whitelists.sh -f failed"

if ! "$ADD_SCRIPT" --check >/dev/null 2>&1; then
  if [ "$AUTO_SETUP" = "1" ]; then
    msg "⚠️  Postfix maps are not wired (MIAB update?) — running --setup"
    "$ADD_SCRIPT" --setup || die "--setup failed"
    alert "Postfix maps were unwired (likely a MIAB update); --setup re-applied automatically."
  else
    die "Postfix maps are not wired and AUTO_SETUP=0 — run: sudo add_whitelists.sh --setup"
  fi
fi

msg "✅ Sync complete."
