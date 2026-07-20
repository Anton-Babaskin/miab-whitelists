#!/usr/bin/env bash
# run_refresh_tests.sh — sandboxed tests for refresh_cloud_senders.sh.
# dig is stubbed with fixtures (SPF recursion, include cycle, DNS failure);
# no network access, never touches the host system.

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
assert_not_grep() {
  if grep -qE -- "$2" "$3" 2>/dev/null; then
    FAIL=$((FAIL+1)); echo "FAIL - $1 (pattern '$2' unexpectedly in $3)"
  else
    PASS=$((PASS+1)); echo "ok   - $1"
  fi
}

# --- sandbox ----------------------------------------------------------------
mkdir -p "$SBX/bin"

# dig stub: fixture DNS. root.test includes sub.test; loop.test cycles back to
# root.test; fail.test simulates a network-level DNS failure (dig rc 9).
cat > "$SBX/bin/dig" <<'EOF'
#!/usr/bin/env bash
domain=""
for a in "$@"; do case "$a" in +*|txt) ;; *) domain="$a" ;; esac; done
case "$domain" in
  root.test) echo '"v=spf1 ip4:192.0.2.0/24 include:sub.test ~all"' ;;
  sub.test)  echo '"v=spf1 ip6:2001:db8::/32 include:loop.test -all"' ;;
  loop.test) echo '"v=spf1 include:root.test ip4:198.51.100.0/24 -all"' ;;
  fail.test) exit 9 ;;
  empty.test) ;;                       # NXDOMAIN / no TXT: empty answer, rc 0
  *) ;;
esac
exit 0
EOF
cat > "$SBX/bin/add_whitelists.sh" <<EOF
#!/usr/bin/env bash
echo "STUB aw \$*" >> "$SBX/calls.log"
exit 0
EOF
chmod +x "$SBX/bin/"*
export PATH="$SBX/bin:$PATH"

# Build script variants with fixture provider lists (PROVIDERS is hardcoded).
mk_variant() { # mk_variant <outfile> <provider> [provider...]
  local out="$1"; shift
  local list=""
  local p; for p in "$@"; do list="${list} \"$p\""; done
  awk -v repl="PROVIDERS=(${list} )" '
    /^PROVIDERS=\(/ {print repl; inblk=1; next}
    inblk && /^\)/  {inblk=0; next}
    !inblk          {print}
  ' "$REPO_DIR/refresh_cloud_senders.sh" > "$out"
  chmod +x "$out"
}
mk_variant "$SBX/rcs_ok.sh"      root.test empty.test
mk_variant "$SBX/rcs_partial.sh" root.test fail.test
mk_variant "$SBX/rcs_dead.sh"    fail.test

cd "$SBX" || exit 1

# --- tests --------------------------------------------------------------------
echo "# happy path: recursion + cycle guard + dedup"
t "expansion succeeds (exit 0)" 0 bash rcs_ok.sh -o out.txt
assert_grep     "ip4 from root SPF"        '^192\.0\.2\.0/24$'      out.txt
assert_grep     "ip4 via include chain"    '^198\.51\.100\.0/24$'   out.txt
assert_grep     "ip6 via include"          '^2001:db8::/32$'        out.txt
assert_grep     "empty.test warned, not fatal" 'нет TXT/SPF'        last.out

echo "# diff mode: first-field comparison ('CIDR OK' lines must not look new)"
printf '192.0.2.0/24 OK\n198.51.100.0/24 OK\n' > cidrmap.txt
t "diff vs cidr-map file" 0 bash rcs_ok.sh -d cidrmap.txt -o new.txt
assert_not_grep "known v4 not reported as new" '^192\.0\.2\.0/24$'  new.txt
assert_grep     "genuinely new v6 reported"    '^2001:db8::/32$'    new.txt

echo "# partial DNS failure: exit 3, --apply refuses"
t "partial run exits 3" 3 bash rcs_partial.sh -o part.txt
assert_grep "partial warning shown" 'DNS-сбо' last.out
assert_grep "collected ranges still written" '^192\.0\.2\.0/24$' part.txt
: > calls.log
t "--apply refused on partial data" 1 bash rcs_partial.sh --apply -o part2.txt
assert_not_grep "add_whitelists not invoked" 'STUB aw' calls.log

echo "# total DNS failure: exit 1, previous output preserved"
echo "PRECIOUS OLD DATA" > dead.txt
t "dead run exits 1" 1 bash rcs_dead.sh -o dead.txt
assert_grep "old output not overwritten" '^PRECIOUS OLD DATA$' dead.txt
assert_not_grep "no phantom ip4=1 counter" 'ip4=1' last.out

echo ""
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
