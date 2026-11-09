#!/usr/bin/env bash
# build-rpms.sh re-stages the distgit sources before every rpmbuild, so that a
# %prep which edits a file in SOURCES in place sees the reviewed input each time.
#
# The case that made this necessary: RDO's neutron %prep runs
#   sed -i 's/\/usr\/bin\/python/\/usr\/bin\/python3/' %{SOURCE36}
# on neutron-destroy-patch-ports.service, and build-rpms.sh runs %prep up to four
# times per package (three -br rounds, then -bb). The 2026-11-09 and 2026-11-10
# builds shipped ExecStart=/usr/bin/python3333 in openstack-neutron-openvswitch
# and in the source RPM.
#
# The function under test is taken from build-rpms.sh itself, not copied here.
# Needs bash, coreutils, awk, sed. No rpm, no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BR="$HERE/../build-rpms.sh"
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/brstage.XXXXXX")"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT

echo "== build-rpms.sh source staging tests =="
fn="$(awk '/^stage_distgit_sources\(\) *\{/,/^}/' "$BR")"
[ -n "$fn" ] && pass "stage_distgit_sources is defined in build-rpms.sh" || { fail "stage_distgit_sources not found"; exit 1; }
eval "$fn"

UNIT_IN='ExecStart=/usr/bin/python -m neutron.cmd.destroy_patch_ports --config-file /etc/neutron/neutron.conf'
setup() {   # a staged distgit copy: a spec, the unit, a file in a subdirectory
    rm -rf "$T/staged" "$T/SOURCES"; mkdir -p "$T/staged/sub" "$T/SOURCES"
    printf 'Name: x\n' > "$T/staged/openstack-neutron.spec"
    printf '[Service]\n%s\n' "$UNIT_IN" > "$T/staged/neutron-destroy-patch-ports.service"
    printf 'patch\n' > "$T/staged/sub/0001-x.patch"
    SRC="$T/SOURCES"
}
prep() {    # exactly what RDO's neutron %prep does to SOURCE36
    sed -i 's/\/usr\/bin\/python/\/usr\/bin\/python3/' "$SRC/neutron-destroy-patch-ports.service"
}
execstart() { grep -o '^ExecStart=[^ ]*' "$SRC/neutron-destroy-patch-ports.service"; }

# --- the old behaviour, to show the mechanism -------------------------------
setup; stage_distgit_sources "$T/staged" >/dev/null
for i in 1 2 3 4; do prep; done
[ "$(execstart)" = "ExecStart=/usr/bin/python3333" ] \
    && pass "staged once, %prep four times: python3333 (the shipped defect, reproduced)" \
    || fail "old behaviour not reproduced" "$(execstart)"

# --- the new behaviour: re-stage before each rpmbuild -----------------------
setup
n="$(stage_distgit_sources "$T/staged")"
[ "$n" = 2 ] && pass "two source files staged, the spec is not one of them" || fail "staged count" "$n"
[ ! -e "$SRC/openstack-neutron.spec" ] && pass "the spec is not copied into SOURCES" || fail "spec copied"
[ -f "$SRC/0001-x.patch" ] && pass "files in subdirectories land flat in SOURCES" || fail "subdirectory file missing"
for i in 1 2 3; do stage_distgit_sources "$T/staged" >/dev/null; prep; done   # three -br rounds
stage_distgit_sources "$T/staged" >/dev/null; prep                            # -bb
[ "$(execstart)" = "ExecStart=/usr/bin/python3" ] \
    && pass "re-staged before each of four %prep runs: ExecStart=/usr/bin/python3" \
    || fail "binary-build input" "$(execstart)"
stage_distgit_sources "$T/staged" >/dev/null                                  # before -bs
[ "$(execstart)" = "ExecStart=/usr/bin/python" ] \
    && pass "the source RPM gets the reviewed input, which one %prep turns into python3" \
    || fail "source-RPM input" "$(execstart)"
grep -qxF "$UNIT_IN" "$T/staged/neutron-destroy-patch-ports.service" \
    && pass "the staged copy itself is never modified" || fail "staged copy modified"

# --- failure is reported, not ignored ----------------------------------------
setup; chmod a-w "$SRC"
if [ "$(id -u)" -ne 0 ]; then
    if stage_distgit_sources "$T/staged" >/dev/null 2>&1; then fail "an unwritable SOURCES must fail"
    else pass "an unwritable SOURCES makes the function fail"; fi
else
    pass "unwritable-SOURCES case skipped as root (root ignores the mode)"
fi
chmod u+w "$SRC"

# --- every rpmbuild in build_one is preceded by a re-stage --------------------
body="$(awk '/^build_one\(\) *\{/,/^}/' "$BR")"
calls="$(grep -nE 'rpmbuild -b[rb] |build_srpm "\$spec" "\$pkg"' <<<"$body" | cut -d: -f1)"
[ "$(wc -l <<<"$calls")" -eq 3 ] && pass "build_one has three rpmbuild steps (-br, -bb, -bs)" \
    || fail "rpmbuild steps in build_one" "$calls"
for ln in $calls; do
    prev="$(sed -n "$((ln-3)),$((ln-1))p" <<<"$body")"
    what="$(sed -n "${ln}p" <<<"$body" | sed 's/^ *//' | cut -c1-40)"
    grep -q 'stage_distgit_sources "\$dir"' <<<"$prev" \
        && pass "re-staged right before: $what" || fail "no re-stage before: $what" "$prev"
done

echo
echo "result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
