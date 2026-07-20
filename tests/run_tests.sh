#!/usr/bin/env bash
# run_tests.sh — functional tests for add_whitelists.sh in a sandbox.
#
# Builds an isolated environment: whitelist paths are rewritten into a temp
# dir and postconf/postmap/postfix/systemctl are replaced with stubs, so the
# tests exercise the real script logic without touching the host system.
#
# Usage: bash tests/run_tests.sh
# Needs root (the script itself requires it); on CI use: sudo env "PATH=$PATH" bash tests/run_tests.sh

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
assert_grep() { # assert_grep <name> <pattern> <file>
  if grep -qE -- "$2" "$3" 2>/dev/null; then
    PASS=$((PASS+1)); echo "ok   - $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL - $1 (pattern '$2' not in $3)"
  fi
}
assert_not_grep() {
  if grep -qE -- "$2" "$3" 2>/dev/null; then
    FAIL=$((FAIL+1)); echo "FAIL - $1 (pattern '$2' unexpectedly in $3)"
  else
    PASS=$((PASS+1)); echo "ok   - $1"
  fi
}

# --- build sandbox -----------------------------------------------------------
mkdir -p "$SBX/bin" "$SBX/etc/postfix" "$SBX/etc/postgrey" "$SBX/var/log"
sed -e "s|/etc/postfix|$SBX/etc/postfix|g" \
    -e "s|/etc/postgrey|$SBX/etc/postgrey|g" \
    -e "s|/var/log|$SBX/var/log|g" \
    "$REPO_DIR/add_whitelists.sh" > "$SBX/aw.sh"
chmod +x "$SBX/aw.sh"

# MIAB-like restrictions chain
echo "permit_sasl_authenticated, permit_mynetworks, reject_non_fqdn_sender, reject_unlisted_recipient, reject_rbl_client zen.spamhaus.org, check_policy_service inet:127.0.0.1:10023" > "$SBX/rr.txt"

cat > "$SBX/bin/postconf" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-h" ]; then cat "$SBX/rr.txt"; exit 0; fi
if [ "\$1" = "-e" ]; then shift; printf '%s\n' "\$*" | sed 's/^smtpd_recipient_restrictions = //' > "$SBX/rr.txt"; exit 0; fi
exit 1
EOF
cat > "$SBX/bin/postmap" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-q" ]; then
  # emulate a hash lookup: exact first-token match in the source file
  key="\$2"; src="\${3#hash:}"; src="\${src#cidr:}"
  grep -qE "^\$(printf '%s' "\$key" | sed 's/[.[\\*^\$/]/\\\\&/g')[[:space:]]" "\$src" && { echo OK; exit 0; } || exit 1
fi
touch "\$1.db"; echo "STUB postmap \$1" >> "$SBX/calls.log"
EOF
cat > "$SBX/bin/postfix" <<EOF
#!/usr/bin/env bash
echo "STUB postfix \$1" >> "$SBX/calls.log"
# controllable failure for rollback tests
if [ "\$1" = "check" ] && [ -f "$SBX/fail_check" ]; then exit 1; fi
exit 0
EOF
cat > "$SBX/bin/systemctl" <<EOF
#!/usr/bin/env bash
echo "STUB systemctl \$*" >> "$SBX/calls.log"
EOF
chmod +x "$SBX/bin/"*
export PATH="$SBX/bin:$PATH"
AW="$SBX/aw.sh"
PF="$SBX/etc/postfix/client_whitelist"
CF="$SBX/etc/postfix/client_whitelist_cidr"
PG="$SBX/etc/postgrey/whitelist_clients.local"

# --- tests -------------------------------------------------------------------
echo "# basic flags"
t "--version exits 0"            0 "$AW" --version
t "no args shows usage (exit 1)" 1 "$AW"

echo "# dry-run must complete (v2.0 regression: crashed under set -e)"
touch "$PF" "$PG"
t "dry-run single entry" 0 "$AW" -n Example.COM
assert_not_grep "dry-run wrote nothing" "example" "$PF"

echo "# mixed batch: routing, duplicates, comments, CRLF (all valid)"
printf 'example.com\r\n1.2.3.4\n198.51.100.0/24\n2001:DB8::/32\n2001:db8::15\nexample.com\n# comment\n   \n' > "$SBX/list.txt"
t "batch import" 0 "$AW" -f "$SBX/list.txt"
assert_grep     "domain in hash map"       '^example\.com OK$'        "$PF"
assert_grep     "ipv4 in hash map"         '^1\.2\.3\.4 OK$'          "$PF"
assert_grep     "cidr4 in cidr map"        '^198\.51\.100\.0/24 OK$'  "$CF"
assert_grep     "cidr6 in cidr map"        '^2001:db8::/32 OK$'       "$CF"
assert_grep     "bare ipv6 in cidr map"    '^2001:db8::15 OK$'        "$CF"
assert_grep     "domain in postgrey"       '^example\.com$'           "$PG"
assert_grep     "cidr6 in postgrey"        '^2001:db8::/32$'          "$PG"
assert_not_grep "cidr NOT in hash map"     '198\.51\.100'             "$PF"
assert_grep     "unwired warning shown"    'not (correctly )?wired'   "$SBX/last.out"
assert_grep     "postfix reloaded"         'STUB postfix reload'      "$SBX/calls.log"
assert_grep     "postgrey reloaded/restarted" 'systemctl (reload|restart) postgrey' "$SBX/calls.log"

echo "# v2.4: transactional batches and real validation"
printf 'valid-host.example.com\nnot_valid_@@\n999.999.999.999\n10.0.0.0/99\n2001:db8::/129\n01.2.3.4\n' > "$SBX/bad.txt"
t "invalid batch aborts with exit 2" 2 "$AW" -f "$SBX/bad.txt"
assert_not_grep "nothing applied on abort" 'valid-host' "$PF"
t "--best-effort applies valid, still exit 2" 2 "$AW" --best-effort -f "$SBX/bad.txt"
assert_grep     "valid entry applied in best-effort" '^valid-host\.example\.com OK$' "$PF"
assert_not_grep "999.999.999.999 rejected"  '999\.999' "$PF"
assert_not_grep "/99 prefix rejected"       '10\.0\.0\.0/99' "$CF"
assert_not_grep "/129 v6 prefix rejected"   '/129' "$CF"
assert_not_grep "leading-zero octet rejected" '01\.2\.3\.4' "$PF"
t "single invalid entry exits 2" 2 "$AW" 999.999.999.999

echo "# duplicates are a no-op (no reload/restart)"
: > "$SBX/calls.log"
t "re-import same batch" 0 "$AW" -f "$SBX/list.txt"
if [ -s "$SBX/calls.log" ]; then FAIL=$((FAIL+1)); echo "FAIL - duplicate run must not touch services"; else PASS=$((PASS+1)); echo "ok   - no service calls on duplicate run"; fi

echo "# --check / --setup"
t "--check before setup exits 2" 2 "$AW" --check
t "--setup wires maps"           0 "$AW" --setup
assert_grep "hash before policy service" 'hash:[^,]*, check_client_access cidr:[^,]*, check_policy_service' "$SBX/rr.txt"
t "--setup is idempotent"        0 "$AW" --setup
if [ "$(grep -o 'hash:' "$SBX/rr.txt" | wc -l)" -eq 1 ]; then PASS=$((PASS+1)); echo "ok   - no duplicate hash token"; else FAIL=$((FAIL+1)); echo "FAIL - duplicate hash token"; fi
t "--check after setup exits 0"  0 "$AW" --check

echo "# partial wiring: only the missing map is added"
echo "permit_mynetworks, reject_unlisted_recipient, check_client_access hash:$PF, check_policy_service inet:127.0.0.1:10023" > "$SBX/rr.txt"
t "--setup completes on partial" 0 "$AW" --setup
if [ "$(grep -o 'hash:' "$SBX/rr.txt" | wc -l)" -eq 1 ] && [ "$(grep -o 'cidr:' "$SBX/rr.txt" | wc -l)" -eq 1 ]; then
  PASS=$((PASS+1)); echo "ok   - partial wiring adds only cidr"
else
  FAIL=$((FAIL+1)); echo "FAIL - partial wiring broke tokens"
fi

echo "# --list"
t "--list exits 0" 0 "$AW" --list
assert_grep "--list shows counters" 'entries' "$SBX/last.out"

echo "# --verify"
t "--verify whitelisted domain exits 0" 0 "$AW" --verify example.com
t "--verify unknown entry exits 1"      1 "$AW" --verify unknown.example.org
t "--verify cidr entry exits 0"         0 "$AW" --verify 198.51.100.0/24

echo "# --remove"
t "--remove existing entry" 0 "$AW" --remove example.com
assert_not_grep "removed from hash map" '^example\.com OK$' "$PF"
assert_not_grep "removed from postgrey" '^example\.com$'    "$PG"
assert_grep     "other entries survive" '^1\.2\.3\.4 OK$'   "$PF"
t "--remove missing entry exits 1" 1 "$AW" --remove nonexistent.example.net
t "--remove without arg fails"     1 "$AW" --remove

echo "# v2.4: --remove refuses regex-looking input, files untouched"
before_pf="$(cat "$PF")"
t "--remove '.*' is refused" 1 "$AW" --remove '.*'
if [ "$(cat "$PF")" = "$before_pf" ]; then
  PASS=$((PASS+1)); echo "ok   - files untouched after refused remove"
else
  FAIL=$((FAIL+1)); echo "FAIL - '.*' modified the whitelist file"
fi

echo "# v2.4: order-aware --check and --setup order repair"
echo "permit_mynetworks, check_policy_service inet:127.0.0.1:10023, check_client_access hash:$PF, check_client_access cidr:$CF" > "$SBX/rr.txt"
t "--check flags misordered maps (exit 2)" 2 "$AW" --check
assert_grep "misorder explained" 'ordering WRONG' "$SBX/last.out"
t "--setup repairs the order" 0 "$AW" --setup
assert_grep "maps re-inserted before policy service" 'hash:[^,]*, check_client_access cidr:[^,]*, check_policy_service' "$SBX/rr.txt"
if [ "$(grep -o 'hash:' "$SBX/rr.txt" | wc -l)" -eq 1 ]; then
  PASS=$((PASS+1)); echo "ok   - no duplicate tokens after repair"
else
  FAIL=$((FAIL+1)); echo "FAIL - duplicate tokens after repair"
fi
t "--check passes after repair" 0 "$AW" --check

echo "# v2.4: --setup rollback when postfix check fails"
echo "permit_mynetworks, check_policy_service inet:127.0.0.1:10023" > "$SBX/rr.txt"
rr_before="$(cat "$SBX/rr.txt")"
touch "$SBX/fail_check"
t "--setup fails when postfix check fails" 1 "$AW" --setup
rm -f "$SBX/fail_check"
if [ "$(cat "$SBX/rr.txt")" = "$rr_before" ]; then
  PASS=$((PASS+1)); echo "ok   - restrictions rolled back after failed check"
else
  FAIL=$((FAIL+1)); echo "FAIL - broken restrictions left behind"
fi

# --- summary -----------------------------------------------------------------
echo ""
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
