#!/usr/bin/env bash
# Tests for the parts of hagistack that a remote compute node depends on:
#   - the compute preflight probes every controller port the node uses
#     (including the Neutron API and Nova metadata) and stops before anything
#     is installed when one is closed;
#   - mgmt_mtu reads the MTU of the interface that holds MGMT_IP, and Neutron's
#     global_physnet_mtu is set from it;
#   - compute-secrets prints only the compute credentials and the RPM set id;
#   - nothing node-specific in the compute path is a fixed value.
#
#   bash rocky10.2/tests/test-compute-node.sh
#
# Functions are taken out of hagistack by their text and run with stubs, so this
# needs no root, no OpenStack and no bash 4. It changes nothing outside a
# temporary directory.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HS="$HERE/../hagistack"

T="$(mktemp -d "${TMPDIR:-/tmp}/hs-compute-test.XXXXXX")" && [ -d "$T" ] || { echo "cannot create a temporary directory" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2" | head -12; }
fn() { sed -n "/^$1() {\( .*\)\{0,1\}\$/,/^}\$/p" "$HS"; }   # a comment may follow the brace

# ---------------------------------------------------------------- preflight
PRE="$(fn phase_compute_preflight)"
[ -n "$PRE" ] && pass "phase_compute_preflight found" || { fail "phase_compute_preflight found"; exit 1; }
pre() {   # pre <closed ports> -> OUT, RC
    OUT="$(env -i PATH="$PATH" CLOSED="$1" bash -c '
        set -euo pipefail
        CONTROLLER_IP=192.0.2.10
        log_step() { :; }; log_ok() { echo "OK: $*"; }; log_error() { echo "ERR: $*"; }
        die() { echo "DIE: $*"; exit 1; }
        phase_mark_done() { echo "MARK $1"; }
        controller_port_open() { echo "PROBE $1" >&2; case " $CLOSED " in *" $1 "*) return 1 ;; esac; return 0; }
        eval "$1"; phase_compute_preflight' _ "$PRE" 2>&1)"
    RC=$?
}
pre ""
for p in 5000 9292 8778 9696 8775 5672 6642 11211; do
    grep -q "^PROBE $p$" <<<"$OUT" && pass "the preflight probes tcp/$p" || fail "the preflight probes tcp/$p" "$OUT"
done
[ "$RC" -eq 0 ] && grep -q "^MARK compute_preflight$" <<<"$OUT" && pass "all ports open: the phase completes" \
    || fail "all ports open: the phase completes" "rc=$RC $OUT"
for p in 9696 8775; do
    pre "$p"
    [ "$RC" -ne 0 ] && grep -q "^DIE: the controller is not reachable" <<<"$OUT" && ! grep -q "^MARK" <<<"$OUT" \
        && grep -q "^ERR: tcp/$p" <<<"$OUT" \
        && pass "tcp/$p closed: stops before anything is installed" || fail "tcp/$p closed: stops" "rc=$RC $OUT"
done
# the preflight runs before the RPM source, repositories and packages
CA="$(fn cmd_compute_add)"
a="$(grep -n '^    phase_compute_preflight$' <<<"$CA" | cut -d: -f1)"
b="$(grep -n '^    phase_rpm_source$' <<<"$CA" | tail -1 | cut -d: -f1)"
[ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && pass "remote compute-add probes the controller before the RPM source" \
    || fail "remote compute-add probes the controller before the RPM source" "preflight=$a rpm=$b"

# ---------------------------------------------------------------- mgmt_mtu
MTU="$(fn mgmt_mtu)
$(fn valid_nic_name)"
mtu() {   # mtu <MGMT_IP> <ip output> <mtu value of eth0> -> OUT
    mkdir -p "$T/sys"; printf '%s\n' "$3" > "$T/sys/eth0"; printf '1500\n' > "$T/sys/eth1"
    OUT="$(env -i PATH="$PATH" IPOUT="$2" S="$T/sys" bash -c '
        set -euo pipefail
        MGMT_IP="$2"
        ip() { printf "%s\n" "$IPOUT"; }
        cat() { case "$1" in /sys/class/net/*/mtu) n="${1#/sys/class/net/}"; command cat "$S/${n%/mtu}" ;; *) command cat "$@" ;; esac; }
        eval "$1"; mgmt_mtu; echo "RC=$?"' _ "$MTU" "$1" 2>&1)"
}
IPS="1: lo    inet 127.0.0.1/8 scope host lo\\       valid_lft forever preferred_lft forever
2: eth1    inet 10.0.0.10/24 brd 10.0.0.255 scope global eth1\\       valid_lft forever
3: eth0    inet 10.0.0.1/24 brd 10.0.0.255 scope global eth0\\       valid_lft forever"
mtu 10.0.0.1 "$IPS" 1460
[ "$OUT" = $'1460\nRC=0' ] && pass "the MTU of the interface holding MGMT_IP (1460, GCE)" || fail "MTU 1460" "$OUT"
mtu 10.0.0.10 "$IPS" 1460
[ "$OUT" = $'1500\nRC=0' ] && pass "the address is matched exactly (10.0.0.10 is not 10.0.0.1)" || fail "exact address match" "$OUT"
mtu 10.0.0.1 "$IPS" 9000
[ "$OUT" = $'9000\nRC=0' ] && pass "a jumbo MTU (9000) is kept" || fail "MTU 9000" "$OUT"
for bad in 1200 99999 abc ""; do
    mtu 10.0.0.1 "$IPS" "$bad"
    [ "$OUT" = "RC=0" ] && pass "an implausible MTU '$bad' prints nothing" || fail "implausible MTU '$bad'" "$OUT"
done
mtu 10.0.0.99 "$IPS" 1460
[ "$OUT" = "RC=0" ] && pass "MGMT_IP on no interface: nothing (Neutron keeps its default)" || fail "MGMT_IP on no interface" "$OUT"
NEU="$(fn phase_neutron)"
grep -q 'mtu="$(mgmt_mtu)"' <<<"$NEU" && grep -q 'ini_set "$NEUTRON_CONF" DEFAULT global_physnet_mtu "$mtu"' <<<"$NEU" \
    && grep -q 'if \[ -n "$mtu" \]; then' <<<"$NEU" \
    && pass "phase_neutron sets global_physnet_mtu from mgmt_mtu, only when it has a value" \
    || fail "phase_neutron sets global_physnet_mtu from mgmt_mtu"

# ---------------------------------------------------------- compute-secrets
CS="$(fn cmd_compute_secrets)"
SK="$(grep -E '^(SECRET_KEYS|COMPUTE_SECRET_KEYS)=' "$HS")"
mkdir -p "$T/etc"
{ echo "# test"; for k in MYSQL_ROOT_PASS KEYSTONE_DB_PASS GLANCE_DB_PASS PLACEMENT_DB_PASS NEUTRON_DB_PASS NOVA_DB_PASS \
      RABBIT_PASS ADMIN_PASSWORD GLANCE_SERVICE_PASS PLACEMENT_SERVICE_PASS NEUTRON_SERVICE_PASS NOVA_SERVICE_PASS \
      METADATA_PROXY_SECRET HORIZON_SECRET_KEY; do echo "$k=synthetic-$k-value"; done; } > "$T/etc/secrets.env"
OUT="$(env -i PATH="$PATH" bash -c '
    set -euo pipefail
    SUDO=""; SECRETS_FILE="$2/etc/secrets.env"
    _need_privilege() { :; }; log_info() { :; }; die() { echo "DIE: $*"; exit 1; }
    eval "$3"
    deploy_load() { DEPLOY_RPM="aaaa"; }
    eval "$(printf "%s\n" "$1" | sed "s/\${DEPLOY\[RPM_SET_SHA256\]:-}/\${DEPLOY_RPM:-}/g; s/\${DEPLOY\[RPM_SET_SHA256\]}/\${DEPLOY_RPM}/g")"
    cmd_compute_secrets' _ "$CS" "$T" "$SK" 2>&1 </dev/null | cat)"
keys="$(grep -vE '^#' <<<"$OUT" | cut -d= -f1 | sort | tr '\n' ' ')"
[ "$keys" = "METADATA_PROXY_SECRET NEUTRON_SERVICE_PASS NOVA_SERVICE_PASS PLACEMENT_SERVICE_PASS RABBIT_PASS RPM_SET_SHA256 " ] \
    && pass "compute-secrets prints the five compute credentials and the RPM set id only" || fail "compute-secrets keys" "$keys / $OUT"
grep -qE 'DB_PASS|ADMIN_PASSWORD|MYSQL_ROOT|HORIZON_SECRET' <<<"$(grep -v '^#' <<<"$OUT")" \
    && fail "compute-secrets prints no database or admin secret" "$OUT" || pass "compute-secrets prints no database or admin secret"

# ------------------------------------------------- no fixed per-node values
NC="$(fn _write_nova_common)"
grep -q 'ini_set "$NOVA_CONF" DEFAULT host "$OS_HOSTNAME"' <<<"$NC" && grep -q 'ini_set "$NOVA_CONF" DEFAULT my_ip "$MGMT_IP"' <<<"$NC" \
    && pass "nova's host and my_ip come from this node (OS_HOSTNAME, MGMT_IP)" || fail "nova host/my_ip per node"
OVN="$(fn phase_ovn)"
grep -q 'external-ids:ovn-encap-ip="$MGMT_IP"' <<<"$OVN" && grep -q 'external-ids:system-id="$OS_HOSTNAME"' <<<"$OVN" \
    && grep -q 'sb_remote="tcp:${CONTROLLER_IP}:${OVN_SB_PORT}"' <<<"$OVN" \
    && pass "the chassis takes this node's name and address and the controller's southbound DB" || fail "chassis per node"
grep -q '^OS_HOSTNAME="$(hostname -s' "$HS" && pass "OS_HOSTNAME is the host's short name, not a fixed value" || fail "OS_HOSTNAME"
COMP="$(fn phase_compute_nova)
$(fn phase_compute_metadata)
$NC"
lit="$(grep -oE '\b(compute[0-9]+|node[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9.]+)\b' <<<"$COMP" | sort -u | tr '\n' ' ')"
[ -z "$lit" ] && pass "the compute phases name no fixed host or address" || fail "the compute phases name no fixed host or address" "$lit"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
