#!/usr/bin/env bash
# Tests for hagistack's ovs_persist_system_id: the OVN chassis name is written to
# system-id.conf before openvswitch starts, so a restart of ovsdb-server
# (`ovs-ctl --system-id=random`) keeps it.
#
#   bash rocky10.2/tests/test-ovs-system-id.sh
#
# Regression for stage 6-6 run s66r3c: the id was set only with ovs-vsctl, a
# restart renamed the chassis to a random UUID, and the metadata agent and the
# router's gateway binding stayed with the old name.
#
# The function is taken out of hagistack by its text and run with stubs, so this
# needs no root, no Open vSwitch and no bash 4. It changes nothing outside a
# temporary directory.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HS="$HERE/../hagistack"

T="$(mktemp -d "${TMPDIR:-/tmp}/hs-sysid-test.XXXXXX")" && [ -d "$T" ] || { echo "cannot create a temporary directory" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2" | head -12; }

FN="$(sed -n '/^ovs_persist_system_id() {$/,/^}$/p' "$HS")"
[ -n "$FN" ] && pass "ovs_persist_system_id found in hagistack" || { fail "ovs_persist_system_id found in hagistack"; exit 1; }

# run <name> <hostname> -> OUT, RC; the conf is $T/<name>/etc/openvswitch/system-id.conf
run() {
    local d="$T/$1"; mkdir -p "$d/etc/openvswitch" "$d/tmp"
    OUT="$(env -i PATH="$PATH" TMPDIR="$d/tmp" LANG="${TEST_LANG:-C}" bash -c '
        set -euo pipefail
        SUDO=""; OS_HOSTNAME="$2"; OVS_SYSTEM_ID_CONF="$3/etc/openvswitch/system-id.conf"
        die() { echo "DIE: $*"; exit 1; }
        log_ok() { echo "OK: $*"; }
        restorecon() { :; }
        eval "$1"
        ovs_persist_system_id
        echo "RETURNED"
    ' _ "$FN" "$2" "$d" 2>&1)"
    RC=$?
}
conf() { cat "$T/$1/etc/openvswitch/system-id.conf" 2>/dev/null; }

# 1: no file yet (first install): the host name is written, readable by all
run c1 host-a
if [ "$RC" -eq 0 ] && [ "$(conf c1)" = "host-a" ] && grep -q RETURNED <<<"$OUT"; then pass "writes the host name when there is no file"
else fail "writes the host name when there is no file" "rc=$RC $OUT"; fi
m="$(ls -l "$T/c1/etc/openvswitch/system-id.conf" | cut -c1-10)"
[ "$m" = "-rw-r--r--" ] && pass "the file is 0644 ($m)" || fail "the file is 0644" "$m"
[ -z "$(ls -A "$T/c1/tmp")" ] && pass "no temporary file is left" || fail "no temporary file is left" "$(ls -A "$T/c1/tmp")"

# 2: ovs-ctl already wrote a random UUID (what s66r3c showed): replaced
mkdir -p "$T/c2/etc/openvswitch"; echo fdb2ff80-097f-4c64-bc92-596eb9d6db46 > "$T/c2/etc/openvswitch/system-id.conf"
run c2 host-b
[ "$RC" -eq 0 ] && [ "$(conf c2)" = "host-b" ] && pass "replaces a random UUID written by ovs-ctl" \
    || fail "replaces a random UUID written by ovs-ctl" "rc=$RC $(conf c2) $OUT"

# 3: already right: left alone, nothing logged
run c3 host-c; touch -t 202001010000 "$T/c3/etc/openvswitch/system-id.conf"
before="$(ls -l "$T/c3/etc/openvswitch/system-id.conf")"
run c3 host-c
[ "$RC" -eq 0 ] && [ "$before" = "$(ls -l "$T/c3/etc/openvswitch/system-id.conf")" ] && ! grep -q "^OK:" <<<"$OUT" \
    && pass "an already correct file is not rewritten" || fail "an already correct file is not rewritten" "rc=$RC $OUT"

# 4: a host name that cannot be a chassis name: refused, the file untouched
for bad in "" "-lead" "a b" 'x"y' 'a/b' 'é'; do
    mkdir -p "$T/c4/etc/openvswitch"; echo keep > "$T/c4/etc/openvswitch/system-id.conf"
    run c4 "$bad"
    if [ "$RC" -ne 0 ] && grep -q "^DIE: the host name" <<<"$OUT" && [ "$(conf c4)" = keep ]; then pass "host name '$bad' refused, file untouched"
    else fail "host name '$bad' refused, file untouched" "rc=$RC $OUT"; fi
done

# 4b: the same in a UTF-8 locale, where [A-Za-z] can match accented letters
loc="$(locale -a 2>/dev/null | grep -iE '^(en_US|C)\.utf-?8$' | sed -n 1p)"
if [ -n "$loc" ]; then
    mkdir -p "$T/c4b/etc/openvswitch"; echo keep > "$T/c4b/etc/openvswitch/system-id.conf"
    TEST_LANG="$loc" run c4b 'é'
    [ "$RC" -ne 0 ] && [ "$(conf c4b)" = keep ] && pass "host name 'é' refused in $loc too" || fail "host name 'é' refused in $loc" "rc=$RC $OUT"
else
    pass "no UTF-8 locale here; the C-locale case above covers the check (not exercised in UTF-8)"
fi

# 5: the directory is missing (Open vSwitch not installed): stops, no file
mkdir -p "$T/c5/tmp"
OUT="$(env -i PATH="$PATH" TMPDIR="$T/c5/tmp" bash -c '
    set -euo pipefail
    SUDO=""; OS_HOSTNAME=host-e; OVS_SYSTEM_ID_CONF="$2/none/system-id.conf"
    die() { echo "DIE: $*"; exit 1; }; log_ok() { echo "OK: $*"; }
    eval "$1"; ovs_persist_system_id; echo RETURNED' _ "$FN" "$T/c5" 2>&1)"; RC=$?
[ "$RC" -ne 0 ] && grep -q "^DIE: cannot write" <<<"$OUT" && [ -z "$(ls -A "$T/c5/tmp")" ] \
    && pass "a missing directory stops the run and leaves no temporary file" || fail "a missing directory stops the run" "rc=$RC $OUT"

# 6: phase_ovn writes the file before it starts openvswitch, and still sets the id
PH="$(sed -n '/^phase_ovn() {$/,/^}$/p' "$HS")"
a="$(grep -n '^    ovs_persist_system_id$' <<<"$PH" | cut -d: -f1)"
b="$(grep -n '^    service_start_enable openvswitch$' <<<"$PH" | cut -d: -f1)"
[ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && pass "phase_ovn writes the file before openvswitch starts" \
    || fail "phase_ovn writes the file before openvswitch starts" "persist=$a start=$b"
grep -q 'ovs_vsctl set open . external-ids:system-id="$OS_HOSTNAME"' <<<"$PH" \
    && pass "phase_ovn still sets the running id (a re-run finds openvswitch running)" || fail "phase_ovn still sets the running id"
# 7: a re-run on a host that ran under another id restarts the metadata agent;
# the block is run with stubs for the current id being the host, a UUID, unset
BLK="$(sed -n '/^    local old_id$/,/^    fi$/p' "$HS")"
rerun() {   # rerun <current id> -> OUT
    OUT="$(env -i PATH="$PATH" CUR="$1" bash -c '
        set -euo pipefail; SUDO=""; OS_HOSTNAME=host-a
        ovs_vsctl() { if [ "$1" = --if-exists ]; then [ -z "$CUR" ] || echo "\"$CUR\""; return 0; fi; echo "SET $*"; }
        service_active() { return 0; }
        systemctl() { echo "RESTART $*"; }
        log_warn() { echo "WARN"; }; log_ok() { :; }; die() { echo DIE; exit 1; }
        eval "f() {
$1
}"; f; echo END' _ "$BLK" 2>&1)"
}
rerun fdb2ff80-097f-4c64-bc92-596eb9d6db46
grep -q "SET set open . external-ids:system-id=host-a" <<<"$OUT" && grep -q "^WARN" <<<"$OUT" \
    && grep -q "RESTART restart neutron-ovn-metadata-agent" <<<"$OUT" && grep -q END <<<"$OUT" \
    && pass "a rename from a UUID sets the host name, warns and restarts the metadata agent" || fail "a rename restarts the metadata agent" "$OUT"
for cur in host-a ""; do
    rerun "$cur"
    grep -q "SET " <<<"$OUT" && ! grep -q "RESTART\|WARN" <<<"$OUT" && grep -q END <<<"$OUT" \
        && pass "current id '${cur}': set, no restart" || fail "current id '${cur}': set, no restart" "$OUT"
done

grep -q '^OVS_SYSTEM_ID_CONF="/etc/openvswitch/system-id.conf"$' "$HS" \
    && pass "the file is /etc/openvswitch/system-id.conf" || fail "the file is /etc/openvswitch/system-id.conf"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
