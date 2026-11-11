#!/usr/bin/env bash
# Tests for packaging/build-own.sh's environment control, with stub dnf/sudo:
#   - every name the definitions produce is excluded from RDO's repository files
#     before the first build, in every section, idempotently;
#   - a waiting definition is retried only once something it missed is built;
#   - the final check refuses a build environment holding one of our names from
#     anywhere but this build, and refuses to call a failed query "clean".
#   bash rocky10.2/tests/test-build-own.sh     (needs python3 >= 3.11 for own_names)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BO="$HERE/../packaging/build-own.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/hs-bo-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2" | head -8; }

# Stubs: sudo runs its arguments; dnf answers from files the tests write.
mkdir -p "$T/bin" "$T/repos" "$T/work/logs"
cat > "$T/bin/sudo" <<'EOS'
#!/bin/sh
exec "$@"
EOS
cat > "$T/bin/dnf" <<'EOS'
#!/bin/sh
# repoquery --whatprovides X (own repository only): listed in $STUB/own-provides
# repoquery --installed: $STUB/installed, or exit $STUB_FAIL
case " $* " in
  *" --whatprovides "*) for a; do last="$a"; done; grep -qxF "$last" "$STUB/own-provides" 2>/dev/null && echo "provider-of-$last"; exit 0 ;;
  *" --installed "*) [ -n "${STUB_FAIL:-}" ] && exit "$STUB_FAIL"; cat "$STUB/installed" 2>/dev/null; exit 0 ;;
esac
exit 0
EOS
chmod +x "$T/bin/sudo" "$T/bin/dnf"
# own_names runs genspec.py, which needs tomllib (Python >= 3.11).
PY=""
for c in python3 python3.13 python3.12 python3.11; do
    command -v "$c" >/dev/null 2>&1 && "$c" -c 'import tomllib' 2>/dev/null && { PY="$(command -v "$c")"; break; }
done
[ -n "$PY" ] && ln -s "$PY" "$T/bin/python3"
export PATH="$T/bin:$PATH" STUB="$T"

lib() {   # lib <shell code>: run code with build-own.sh's functions loaded
    BUILD_OWN_LIB_ONLY=1 BUILD_OWN_REPO_DIR="$T/repos" WORK="$T/work" HOME="$T/home" \
        bash -c 'source "$1"; shift; eval "$1"' _ "$BO" "$1"
}

echo "== build-own.sh environment control"

# --- the library mode loads the functions and builds nothing -----------------
out="$(lib 'type exclude_from_rdo ready env_not_own own_names missing_deps >/dev/null && echo loaded' 2>&1)"
[ "$out" = loaded ] && pass "library mode loads the functions and runs nothing else" || fail "library mode" "$out"
out="$(BUILD_OWN_LIB_ONLY=1 WORK="$T/work" HOME="$T/home" bash "$BO" 2>&1; echo "rc=$?")"
[ "$out" = "rc=0" ] && pass "library mode executed (not sourced) exits at once" || fail "library mode executed" "$out"

# --- exclusion: every section, also one without enabled=1; idempotent ----------
cat > "$T/repos/delorean.repo" <<'EOF'
[delorean]
name=delorean
baseurl=https://example.invalid/current
enabled=1
gpgcheck=0

[delorean-component-common]
name=common
baseurl=https://example.invalid/common
gpgcheck=0
EOF
cat > "$T/repos/delorean-deps.repo" <<'EOF'
[delorean-master-testing]
name=deps
baseurl=https://example.invalid/deps
enabled=1
EOF
printf 'python3-oslo-log\npython3-oslo-db+mysql\n' > "$T/names"
lib "exclude_from_rdo '$T/names' && exclude_from_rdo '$T/names'" || fail "exclude_from_rdo ran" "rc=$?"
n_sec=$(grep -c '^\[' "$T/repos/delorean.repo" "$T/repos/delorean-deps.repo" | awk -F: '{s+=$2} END {print s}')
n_exc=$(grep -c '^exclude=python3-oslo-log python3-oslo-db+mysql # hagistack-own$' "$T/repos/delorean.repo" "$T/repos/delorean-deps.repo" | awk -F: '{s+=$2} END {print s}')
[ "$n_sec" -eq 3 ] && [ "$n_exc" -eq 3 ] \
    && pass "every section of both RDO files gets one exclude line, also a section without enabled=1; a second run adds none" \
    || fail "exclusion lines" "sections=$n_sec excludes=$n_exc: $(cat "$T/repos/delorean.repo")"
awk '/^\[delorean-component-common\]/{getline; print}' "$T/repos/delorean.repo" | grep -q '^exclude=' \
    && pass "the exclude line follows the section header" || fail "exclude placement" "$(cat "$T/repos/delorean.repo")"
grep -q '^baseurl=https://example.invalid/common$' "$T/repos/delorean.repo" \
    && pass "the rest of the repository file is kept" || fail "repository file kept"

# --- own_names: every package of every definition, once ------------------------
if [ -n "$PY" ]; then
    out="$(lib 'own_names' 2>&1)"; n=$(printf '%s\n' "$out" | grep -c .); u=$(printf '%s\n' "$out" | sort -u | grep -c .)
    want=$(cat "$HERE"/../packaging/defs/*.toml | grep -c '^\[\[package\]\]')
    [ "$n" -eq "$want" ] && [ "$u" -eq "$n" ] && printf '%s\n' "$out" | grep -qx 'python3-oslo-log' \
        && pass "own_names lists all $n package names of the definitions, each once" \
        || fail "own_names" "listed=$n unique=$u packages-in-defs=$want"
else
    fail "own_names" "no python3 >= 3.11 with tomllib here; not run"
fi

# --- missing_deps / ready -------------------------------------------------------
printf 'error: Failed build dependencies:\n\tpython3dist(oslo-log) >= 4.6.1 is needed by python-x-1.0-1.el10.noarch\n\tpython3dist(fixtures) is needed by python-x-1.0-1.el10.noarch\n' \
    > "$T/work/logs/python-x.rpmbuild.log"
got="$(lib 'missing_deps python-x' | tr '\n' ' ')"
[ "$got" = "python3dist(fixtures) python3dist(oslo-log) " ] && pass "missing_deps reads rpmbuild's missing build dependencies" || fail "missing_deps" "$got"
lib 'missing_deps python-x > "$LOGDIR/python-x.missing"'
: > "$T/own-provides"
lib 'ready python-x' && fail "ready: nothing it missed is built yet, yet retried" || pass "a waiting definition is not retried while nothing it missed is built"
echo 'python3dist(oslo-log)' > "$T/own-provides"
lib 'ready python-x' && pass "it is retried once a dependency it missed is provided by this build" || fail "ready after the dependency is built"
lib 'ready python-y' && pass "a definition with no record of what it missed is retried" || fail "ready without a record"

# --- the final check --------------------------------------------------------------
printf 'python3-oslo-log\npython3-oslo-db\n' > "$T/work/own-names.txt"
printf 'bash @System\npython3-oslo-log hagistack-own\npython3-oslo-db hagistack-own\n' > "$T/installed"
out="$(lib 'env_not_own'; echo "rc=$?")"
[ "$out" = "rc=0" ] && pass "a build environment whose packages with our names all came from this build is clean" || fail "clean environment" "$out"
printf 'bash @System\npython3-oslo-log delorean-component-common\npython3-oslo-db hagistack-own\n' > "$T/installed"
out="$(lib 'env_not_own')"
[ "$out" = "python3-oslo-log delorean-component-common" ] && pass "one of our names from RDO trunk is reported, with its repository" || fail "stray package" "$out"
: > "$T/installed"
lib 'env_not_own' >/dev/null; rc=$?
[ "$rc" -eq 2 ] && pass "an empty installed-package list is not taken as clean" || fail "empty query" "rc=$rc"
STUB_FAIL=1 lib 'env_not_own' >/dev/null; rc=$?
[ "$rc" -eq 2 ] && pass "a failed query is not taken as clean" || fail "failed query" "rc=$rc"

# --- the main run wires the pieces in order --------------------------------------
m="$(grep -n -E '^own_names >|^exclude_from_rdo |^for n in "\$\{WANT\[@\]\}"; do stage|^round=0|^stray=|^write_lock$' "$BO" | cut -d: -f1 | tr '\n' ' ')"
set -- $m
[ "$#" -eq 6 ] && [ "$1" -lt "$2" ] && [ "$2" -lt "$3" ] && [ "$3" -lt "$4" ] && [ "$4" -lt "$5" ] && [ "$5" -lt "$6" ] \
    && pass "the run stages, then excludes our names, then builds, then writes the lock, then checks the environment" \
    || fail "order in the main run" "lines: $m"
grep -q 'stray="$(env_not_own)" || die' "$BO" && grep -q '\[ -z "$stray" \] || die' "$BO" \
    && pass "a stray package or a failed check stops the run (STOP)" || fail "the check does not stop the run"
grep -q 'sed -i.*hagistack-own' "$BO" && fail "publish_repo still rewrites the exclusion per build" || pass "the exclusion is no longer recomputed from what is built so far"

echo
echo "build-own.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
