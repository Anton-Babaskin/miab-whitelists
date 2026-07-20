#!/usr/bin/env bash
# run_sync_tests.sh — sandboxed tests for sync_whitelists.sh.
# Stubs git/add_whitelists.sh/logger/mail; never touches the host system.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SBX="$(mktemp -d)"
trap 'rm -rf "$SBX"' EXIT

PASS=0
FAIL=0
t() { # t <name> <expected-exit> cmd...
  local name="$1" want="$2"; shift 2
  local got=0
  "$@" >"$SBX/last.out" 2>&1 || got=$?
  if [ "$got" -eq "$want" ]; then
    PASS=$((PASS+1)); echo "ok   - $name"
  else
    FAIL=$((FAIL+1)); echo "FAIL - $name (exit $got, want $want)"
    sed 's/^/       /' "$SBX/last.out"
  fi
}
assert_grep() {
  if grep -qE -- "$2" "$3" 2>/dev/null; then
    PASS=$((PASS+1)); echo "ok   - $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL - $1 (pattern '$2' not in $3)"
  fi
}

# --- sandbox ----------------------------------------------------------------
mkdir -p "$SBX/bin" "$SBX/wlrepo/.git"
echo "example.com" > "$SBX/wlrepo/whitelist.txt"
SYNC="$REPO_DIR/sync_whitelists.sh"

cat > "$SBX/bin/git" <<EOF
#!/usr/bin/env bash
echo "STUB git \$*" >> "$SBX/calls.log"
for a in "\$@"; do case "\$a" in rev-parse) echo 0123456789abcdef; exit 0;; esac; done
exit 0
EOF
cat > "$SBX/bin/add_whitelists.sh" <<EOF
#!/usr/bin/env bash
echo "STUB aw \$*" >> "$SBX/calls.log"
if [ "\$1" = "--check" ]; then exit "\$(cat "$SBX/check.rc")"; fi
exit 0
EOF
cat > "$SBX/bin/logger" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$SBX/bin/"*
export PATH="$SBX/bin:$PATH"

cat > "$SBX/sync.conf" <<EOF
REPO_DIR="$SBX/wlrepo"
WHITELIST_FILE="whitelist.txt"
ADD_SCRIPT="$SBX/bin/add_whitelists.sh"
AUTO_SETUP=1
ALERT_EMAIL=""
EOF

# --- tests --------------------------------------------------------------------
t "--version exits 0" 0 bash "$SYNC" --version
t "missing config fails" 1 bash "$SYNC" -c "$SBX/nope.conf"

echo "# happy path: maps wired (check exits 0)"
echo 0 > "$SBX/check.rc"; : > "$SBX/calls.log"
t "sync cycle succeeds" 0 bash "$SYNC" -c "$SBX/sync.conf"
assert_grep "git pull ran"       'git .*pull --ff-only'          "$SBX/calls.log"
assert_grep "whitelist applied"  "aw -f $SBX/wlrepo/whitelist.txt" "$SBX/calls.log"
assert_grep "wiring checked"     'aw --check'                    "$SBX/calls.log"
if grep -q 'aw --setup' "$SBX/calls.log"; then
  FAIL=$((FAIL+1)); echo "FAIL - --setup must not run when wired"
else
  PASS=$((PASS+1)); echo "ok   - no --setup when wired"
fi

echo "# unwired maps (check exits 2) -> automatic --setup"
echo 2 > "$SBX/check.rc"; : > "$SBX/calls.log"
t "sync heals unwired maps" 0 bash "$SYNC" -c "$SBX/sync.conf"
assert_grep "--setup re-applied" 'aw --setup' "$SBX/calls.log"

echo "# broken repo path"
cat > "$SBX/bad.conf" <<EOF
REPO_DIR="$SBX/does-not-exist"
ADD_SCRIPT="$SBX/bin/add_whitelists.sh"
EOF
t "missing repo fails" 1 bash "$SYNC" -c "$SBX/bad.conf"

echo ""
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
