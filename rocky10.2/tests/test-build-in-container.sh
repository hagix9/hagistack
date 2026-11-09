#!/usr/bin/env bash
# Tests for the pass control in build-in-container.sh: how the results of
# build-rpms.sh passes are judged, when a second pass runs, and when the
# build stops. build-rpms.sh itself is not run: run_pass is replaced by a
# scripted fake, so every exit status / results-file shape can be produced.
#
#   bash rocky10.2/tests/test-build-in-container.sh
#
# Needs bash 4+, awk, comm and (for the collect tests) createrepo_c. Changes
# nothing outside a temporary directory.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIC="$HERE/../build-in-container.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/hs-bic-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2" | head -8; }

# A small manifest with every row kind build-rpms.sh knows.
mkdir -p "$T/src"
cat > "$T/src/gazpacho.manifest" <<'EOF'
# comment
KEY 0xabc 0000000000000000000000000000000000000000000000000000000000000000
alpha  alpha-distgit  c1 a.spec 1.0 1 alpha-1.0.tar.gz 00 alpha 0xabc
beta   beta-distgit   c2 b.spec 1.0 1 beta-1.0.tar.gz  00 beta  0xabc
gamma  gamma-distgit  c3 g.spec 1.0 1 gamma-1.0.tar.gz 00 gamma 0xabc
#DISABLED omega omega-distgit c4 o.spec 1.0 1 omega-1.0.tar.gz 00 omega 0xabc
PYPI python3-delta delta 1.0 delta-1.0.tar.gz 00 MIT a summary
SPEC alpha a.spec 00 00
PATCH beta x.patch 00
EOF

# run_case <name> <scenario-body>
#   The scenario defines fake_pass1 / fake_pass2 (each gets the package
#   arguments, writes $OUT/logs/passN.results and passN.log, and returns the
#   exit status build-rpms.sh would have), then calls build_all.
run_case() {
    local d="$T/case-$1"; rm -rf "$d"; mkdir -p "$d/out/logs" "$d/build/work/logs"
    OUT="$(BIC_LIB_ONLY=1 BIC_SRC="$T/src" BIC_BUILD="$d/build" BIC_OUT="$d/out" \
        bash -c '
            source "$1"
            L="$LOG_DIR"; W="$BUILD_DIR/work/logs"
            run_pass() {
                local n="$1"; shift
                echo "RUN-PASS $n: $*" >> "$L/calls"
                "fake_pass$n" "$@"
            }
            eval "$2"
            build_all "$BIC_SRC/gazpacho.manifest" && echo "BUILD-ALL-OK count=$EXPECTED_COUNT"
        ' _ "$BIC" "$2" 2>&1)"
    RC=$?
    CALLS="$(cat "$d/out/logs/calls" 2>/dev/null)"
}
ok_case()   { if [ "$RC" -eq 0 ] && grep -q BUILD-ALL-OK <<<"$OUT"; then pass "$1"; else fail "$1" "rc=$RC $OUT"; fi; }
stop_case() {  # stop_case <name> <regex>
    if [ "$RC" -ne 0 ] && ! grep -q BUILD-ALL-OK <<<"$OUT" && grep -qE "$2" <<<"$OUT"; then pass "$1"
    else fail "$1" "rc=$RC wanted /$2/: $OUT"; fi
}
no_pass2() { if grep -q 'RUN-PASS 2' <<<"$CALLS"; then fail "$1: pass 2 must not run" "$CALLS"; else pass "$1: pass 2 did not run"; fi; }

ALL4='printf "PASS alpha (built)\nPASS beta (built)\nPASS gamma (built)\nPASS python3-delta (PyPI; built)\n"'
DEP_BETA='printf "error: Failed build dependencies:\n\tpython3dist(x) >= 1 is needed by beta-1.0\n" > "$W/beta.rpmbuild.log"'

echo "== build-in-container.sh pass control tests =="

# --- normal behaviour -------------------------------------------------------
run_case normal2 "
fake_pass1() { $DEP_BETA; printf 'PASS alpha (built)\nFAIL beta (rpmbuild exit 11)\nPASS gamma (built)\nPASS python3-delta (PyPI; built)\n' > \$L/pass1.results; echo ok > \$L/pass1.log; return 1; }
fake_pass2() { printf 'PASS beta (built)\n' > \$L/pass2.results; echo ok > \$L/pass2.log; return 0; }"
ok_case "two-pass: a build-dependency failure in pass 1 is rebuilt in pass 2"
grep -qx 'RUN-PASS 2: beta' <<<"$CALLS" && pass "two-pass: pass 2 builds exactly the failed package" || fail "two-pass: pass 2 arguments" "$CALLS"
grep -q "count=4" <<<"$OUT" && pass "two-pass: 4 expected packages (KEY/SPEC/PATCH/#DISABLED excluded, PYPI by rpm name)" || fail "expected count" "$OUT"

run_case normal1 "
fake_pass1() { $ALL4 > \$L/pass1.results; echo ok > \$L/pass1.log; return 0; }"
ok_case "one pass: everything built, done"
no_pass2 "one pass"

# --- pass 1 abnormal --------------------------------------------------------
run_case stop1 "
fake_pass1() { printf '\nSTOP: digest mismatch for x\n' > \$L/pass1.log; return 1; }"
stop_case "pass 1 STOP (verification failure) stops the build" "nothing is retried after a STOP"
no_pass2 "pass 1 STOP"

run_case stop1res "
fake_pass1() { printf 'PASS alpha (built)\n' > \$L/pass1.results; printf 'STOP: signature\n' > \$L/pass1.log; return 1; }"
stop_case "pass 1 STOP wins even when a results file exists" "STOP"
no_pass2 "pass 1 STOP with results"

run_case missing1 "
fake_pass1() { echo crashed > \$L/pass1.log; return 1; }"
stop_case "pass 1 abnormal exit without a results file stops" "results file .* is missing"
no_pass2 "pass 1 missing results"

run_case missing1rc0 "
fake_pass1() { echo ok > \$L/pass1.log; return 0; }"
stop_case "pass 1 exit 0 without a results file stops" "is missing"

run_case empty1 "
fake_pass1() { : > \$L/pass1.results; echo ok > \$L/pass1.log; return 0; }"
stop_case "pass 1 empty results file stops" "is empty"

run_case corrupt1 "
fake_pass1() { $ALL4 > \$L/pass1.results; echo 'garbage line' >> \$L/pass1.results; echo ok > \$L/pass1.log; return 0; }"
stop_case "pass 1 corrupt results line stops" "malformed"

run_case trunc1 "
fake_pass1() { printf 'PASS alpha (built)\nPASS beta (built)\nPASS gamma (bu' > \$L/pass1.results; echo ok > \$L/pass1.log; return 0; }"
stop_case "pass 1 truncated results file stops" "malformed|incomplete"

run_case incomplete1 "
fake_pass1() { printf 'PASS alpha (built)\nPASS beta (built)\nPASS gamma (built)\n' > \$L/pass1.results; echo ok > \$L/pass1.log; return 0; }"
stop_case "pass 1 results missing a package stops (partial set)" "incomplete; no result for: python3-delta"

run_case dup1 "
fake_pass1() { $ALL4 > \$L/pass1.results; echo 'PASS alpha (again)' >> \$L/pass1.results; echo ok > \$L/pass1.log; return 0; }"
stop_case "pass 1 duplicated package stops" "twice"

run_case extra1 "
fake_pass1() { $ALL4 > \$L/pass1.results; echo 'PASS omega (built)' >> \$L/pass1.results; echo ok > \$L/pass1.log; return 0; }"
stop_case "pass 1 result for a package not in the manifest stops" "not asked for: omega"

run_case nonretry1 "
fake_pass1() { printf 'PASS alpha (built)\nFAIL beta (rpmbuild exit 1)\nPASS gamma (built)\nPASS python3-delta (PyPI; built)\n' > \$L/pass1.results; echo ok > \$L/pass1.log; return 1; }"
stop_case "pass 1 non-dependency failure (exit 1) is not retried" "cannot fix .*beta\\(1\\)"
no_pass2 "pass 1 non-dependency failure"

run_case nolog11 "
fake_pass1() { echo 'some other error' > \$W/beta.rpmbuild.log; printf 'PASS alpha (built)\nFAIL beta (rpmbuild exit 11)\nPASS gamma (built)\nPASS python3-delta (PyPI; built)\n' > \$L/pass1.results; echo ok > \$L/pass1.log; return 1; }"
stop_case "exit 11 without 'is needed by' in the package log is not retried" "not a build-dependency failure"
no_pass2 "exit 11 without dependency evidence"

run_case rc0fail "
fake_pass1() { $DEP_BETA; printf 'PASS alpha (built)\nFAIL beta (rpmbuild exit 11)\nPASS gamma (built)\nPASS python3-delta (PyPI; built)\n' > \$L/pass1.results; echo ok > \$L/pass1.log; return 0; }"
stop_case "pass 1 exit 0 but a FAIL in the results stops (inconsistent)" "exited 0 but its results list failures"
no_pass2 "pass 1 inconsistent exit 0"

run_case rc1nofail "
fake_pass1() { $ALL4 > \$L/pass1.results; echo ok > \$L/pass1.log; return 1; }"
stop_case "pass 1 non-zero exit with all PASS stops (inconsistent)" "results list no failure"
no_pass2 "pass 1 inconsistent non-zero"

# --- pass 2 abnormal --------------------------------------------------------
P1BETA="fake_pass1() { $DEP_BETA; printf 'PASS alpha (built)\nFAIL beta (rpmbuild exit 11)\nPASS gamma (built)\nPASS python3-delta (PyPI; built)\n' > \$L/pass1.results; echo ok > \$L/pass1.log; return 1; }"

run_case stop2 "$P1BETA
fake_pass2() { printf 'STOP: digest mismatch\n' > \$L/pass2.log; return 1; }"
stop_case "pass 2 STOP stops the build" "pass 2 stopped"

run_case missing2 "$P1BETA
fake_pass2() { echo crashed > \$L/pass2.log; return 1; }"
stop_case "pass 2 abnormal exit without results stops" "pass 2 .* is missing"

run_case corrupt2 "$P1BETA
fake_pass2() { echo 'PASS beta' > \$L/pass2.results; echo ok > \$L/pass2.log; return 0; }"
stop_case "pass 2 corrupt results stops" "malformed"

run_case still2 "$P1BETA
fake_pass2() { echo 'FAIL beta (rpmbuild exit 1)' > \$L/pass2.results; echo ok > \$L/pass2.log; return 1; }"
stop_case "a package failing in both passes stops (partial set never accepted)" "failed in both passes: beta"

run_case rc2 "$P1BETA
fake_pass2() { echo 'PASS beta (built)' > \$L/pass2.results; echo ok > \$L/pass2.log; return 1; }"
stop_case "pass 2 non-zero exit with PASS results stops (inconsistent)" "pass 2 exited 1"

run_case wrongset2 "$P1BETA
fake_pass2() { printf 'PASS beta (built)\nPASS alpha (built)\n' > \$L/pass2.results; echo ok > \$L/pass2.log; return 0; }"
stop_case "pass 2 results for packages it was not asked to build stop" "not asked for: alpha"

run_case empty2 "$P1BETA
fake_pass2() { : > \$L/pass2.results; echo ok > \$L/pass2.log; return 0; }"
stop_case "pass 2 empty results stop" "is empty"

# --- collecting: a partial RPM set is never published -------------------------
collect_case() {  # collect_case <name> <number-of-srpms> <number-of-rpms>
    local d="$T/collect-$1"; rm -rf "$d"
    mkdir -p "$d/out/logs" "$d/build/rpmbuild/RPMS/noarch" "$d/build/rpmbuild/SRPMS" "$d/build/work/logs"
    local i
    for i in $(seq 1 "$3"); do echo x > "$d/build/rpmbuild/RPMS/noarch/p$i-1.0-1.noarch.rpm"; done
    for i in $(seq 1 "$2"); do echo x > "$d/build/rpmbuild/SRPMS/p$i-1.0-1.src.rpm"; done
    OUT="$(BIC_LIB_ONLY=1 BIC_SRC="$T/src" BIC_BUILD="$d/build" BIC_OUT="$d/out" bash -c '
        source "$1"; createrepo_c() { mkdir -p "${@: -1}/repodata"; }
        EXPECTED_COUNT=4; collect_result && echo COLLECT-OK' _ "$BIC" 2>&1)"
    RC=$?; OKFILE="$d/out/logs/build.ok"
}
collect_case short 3 5
if [ "$RC" -ne 0 ] && grep -q "incomplete" <<<"$OUT" && [ ! -e "$OKFILE" ]; then
    pass "collect: fewer SRPMs than manifest packages is refused, build.ok not written"
else fail "collect: incomplete set" "rc=$RC $OUT"; fi
collect_case norpm 4 0
if [ "$RC" -ne 0 ] && [ ! -e "$OKFILE" ]; then pass "collect: no binary RPM is refused"; else fail "collect: no RPM" "$OUT"; fi
collect_case full 4 6
if [ "$RC" -eq 0 ] && grep -qx 'packages=4 rpms=6 srpms=4' "$OKFILE" 2>/dev/null; then
    pass "collect: complete set writes build.ok last"
else fail "collect: complete set" "rc=$RC $OUT"; fi

# --- the real manifest ------------------------------------------------------
n="$(BIC_LIB_ONLY=1 bash -c 'source "$1"; expected_packages "$2" | wc -l' _ "$BIC" "$HERE/../gazpacho.manifest")"
rows="$(awk '$0 !~ /^[[:space:]]*($|#)/ && $1!="KEY" && $1!="SPEC" && $1!="PATCH"' "$HERE/../gazpacho.manifest" | wc -l)"
if [ "$n" -eq "$rows" ] && [ "$n" -eq 69 ]; then
    pass "gazpacho.manifest: 69 packages expected (59 distgit + 10 PYPI), as the 2026-11-09 build produced 69 SRPMs"
else fail "gazpacho.manifest package count" "expected_packages=$n rows=$rows"; fi

echo
echo "result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
