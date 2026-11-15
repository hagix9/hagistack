#!/bin/bash
# s67-cluster.sh — the fixed steps of the controller + compute acceptance
# (stage 6-6-R5) on two Rocky Linux 10.2 x86_64 nodes of one run:
#
#   n1  controller   <run id>-n1: builds the set (s66-node.sh preflight .. pack),
#                    then `hagistack controller`
#   n2  compute      <run id>-n2: `hagistack compute-add --controller-ip`
#
#   sudo bash /var/tmp/hs6/tree/acceptance/stage6/s67-cluster.sh run STEP
#   sudo bash /var/tmp/hs6/tree/acceptance/stage6/s67-cluster.sh status
#
# Like s66-node.sh: it is run only through `hs6.py ssh` with the commands of
# run-plan.json at the approved commit, each step runs once as a transient
# service, and nothing is taken from the command line but the step name. The
# role comes from the host name (-n1 controller, -n2 compute); a step of the
# other role refuses.
#
# Steps, in the order they are run across the two nodes:
#   n1 controller   hagistack controller with the new set; what a controller
#                   with no compute node must and must not do; the controller's
#                   firewall opened as README says; compute-secrets and
#                   rpm-bundle written and offered once to n2 (below)
#   n2 compute      the handoff fetched from n1; the credentials installed as
#                   README says; compute-add --controller-ip with the bundle;
#                   what a compute node must and must not have
#   n1 cluster      the compute node registered (Nova, Placement, OVN chassis
#                   set, agents); guests on n2 reached over floating IPs through
#                   the Geneve tunnel (SSH, metadata, a 2 MB stream; guest to
#                   guest is local to n2); the controller's units restarted; the compute node
#                   back, a new guest, traffic; tracebacks after recovery
#   n2 reboot       this node reboots (the step returns before it does)
#   n1 after-reboot the compute node registered again under the same chassis
#                   name; its guests started again and reachable
#   n2 rerun        compute-add again: configuration unchanged, services running
#   n1 final        a new guest after the re-run, traffic, tracebacks
#   n1 evidence-c   evidence-cluster.tar   (runs once controller has started)
#   n2 evidence-n   evidence-compute.tar   (runs once compute has started)
#
# The handoff (controller -> compute) stands in for README's "copy the file to
# the new node over a secure channel": the two nodes share no SSH key, so n1
# offers one tar (compute-secrets and the RPM bundle) once, on its management
# address, to n2's address only (a runtime firewalld rule for that source), for
# at most one hour. n2 sends back the SHA-256 of what it received and n1 answers
# whether it matches; neither prints it. The transfer is plain TCP inside the
# run's own VPC, which only the run's nodes use. n1 deletes its copy after the
# transfer, n2 deletes its copy of the credentials once installed.
#
# Never written to the output or the evidence: /etc/hagistack (credentials,
# guest key), the handoff, tokens. Evidence is scanned as in s66-node.sh.
set -uo pipefail

S67_SELF="$(readlink -f "${BASH_SOURCE[0]}")"
. "$(dirname "$S67_SELF")/s66-node.sh"      # helpers only (it returns before running anything)
STEP="${1:-}"
FAILS=0

HANDOFF="$BASE/handoff"
HANDOFF_PORT=47001
HANDOFF_UNIT=hs6-handoff            # helper units; never the name of a step's unit (hs6-STEP)
REBOOT_UNIT=hs6-reboot-timer
PROVIDER_ARGS=(--ext-nic hgext0 --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1
               --floating-start 172.24.4.100 --floating-end 172.24.4.200)
CONTROLLER_PORTS="5000 9292 8778 9696 8775 5672 6642 11211"   # README, "For a second node"
COMPUTE_SECRET_NAMES="METADATA_PROXY_SECRET NEUTRON_SERVICE_PASS NOVA_SERVICE_PASS PLACEMENT_SERVICE_PASS RABBIT_PASS RPM_SET_SHA256"
CTRL_STEPS="controller cluster after-reboot final evidence-c"
COMP_STEPS="compute reboot rerun evidence-n"
ALL_STEPS="$CTRL_STEPS $COMP_STEPS"

HOST="$(hostname -s)"
case "$HOST" in
    *-n1) ROLE=controller; PEER="${HOST%-n1}-n2"; STEPS="$CTRL_STEPS" ;;
    *-n2) ROLE=compute;    PEER="${HOST%-n2}-n1"; STEPS="$COMP_STEPS" ;;
    *)    ROLE="";         PEER="";               STEPS="" ;;
esac

# ----------------------------------------------------------------- helpers --
my_ip(){ ip -4 route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'; }
peer_ip(){ getent ahostsv4 "$PEER" 2>/dev/null | awk '{print $1; exit}'; }
is_ipv4(){ [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }
nic_mtu(){   # the MTU of the interface holding address $1
    local ifc; ifc="$(ip -o -4 addr show | awk -v ip="$1" '{split($4, a, "/"); if (a[1] == ip) {print $2; exit}}')"
    [ -n "$ifc" ] && cat "/sys/class/net/$ifc/mtu"
}
ntp_synced(){ [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ]; }
units_active(){ local u; for u in "$@"; do systemctl is-active --quiet "$u" || return 1; done; }
time_check() { check "the clock is synchronised (timedatectl NTPSynchronized=yes)" wait_until 300 ntp_synced; }
# the active keys of a section of an ini file (comments are not values)
ini_active() {   # ini_active <file> <section> <key-regex>
    awk -v s="[$2]" -v k="$3" '
        /^[[:space:]]*\[/ { cur = $0; gsub(/[[:space:]]/, "", cur); next }
        cur == s && $0 ~ "^[[:space:]]*(" k ")[[:space:]]*=" { print FNR }' "$1"
}
secret_names(){ grep -vE '^[[:space:]]*(#|$)' "$1" | cut -d= -f1 | sort | tr '\n' ' ' | sed 's/ $//'; }
open_firewall() {   # open_firewall <tcp ports> <udp ports>: README's commands, only when firewalld runs
    systemctl is-active --quiet firewalld || { note "firewalld is not running; nothing to open"; return 0; }
    local p a=()
    for p in $1; do a+=(--add-port="$p/tcp"); done
    for p in $2; do a+=(--add-port="$p/udp"); done
    firewall-cmd --permanent "${a[@]}" >/dev/null && firewall-cmd --reload >/dev/null
    check "firewalld opened as README says ($1${1:+ tcp, }$2 udp; an operator step, not done by hagistack)" \
        firewall_has "$1" "$2"
}
firewall_has() {
    local p have; have=" $(firewall-cmd --list-ports 2>/dev/null) "
    for p in $1; do [[ "$have" == *" $p/tcp "* ]] || return 1; done
    for p in $2; do [[ "$have" == *" $p/udp "* ]] || return 1; done
}
save_times(){ printf '%s=%s\n' "$@" >> "$OUT/cluster-times.env"; }
load_times(){ [ -f "$OUT/cluster-times.env" ] && . "$OUT/cluster-times.env"; }

# controller side: guests are reached through floating IPs from this host, so
# every packet to them crosses the Geneve tunnel to the compute node
compute_up(){ os_ compute service list --service nova-compute --host "$PEER" -f value -c State | grep -qx up; }
hypervisor_on_peer(){ os_ hypervisor list -f value -c "Hypervisor Hostname" -c State | grep -E "^$PEER(\.| )" | grep -q ' up$'; }
host_of(){ os_ server show "$1" -f value -c OS-EXT-SRV-ATTR:host; }
server_status(){ os_ server show "$1" -f value -c status; }
peer_gone() {   # nova-compute reported down, or s67-g1 silent three times in a row
    local f i
    os_ compute service list --service nova-compute --host "$PEER" -f value -c State | grep -qx down && return 0
    f="$(fip_of s67-g1)"; [ -n "$f" ] || return 1
    for i in 1 2 3; do fip_ssh "$f" true >/dev/null 2>&1 && return 1; sleep 5; done
    return 0
}
chassis_set(){ timeout 30 ovn-sbctl --bare --columns=name list Chassis 2>/dev/null | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//'; }
chassis_pair(){ [ "$(chassis_set)" = "$(printf '%s\n' "$HOST" "$PEER" | sort | tr '\n' ' ' | sed 's/ $//')" ]; }
chassis_field(){ timeout 30 ovn-sbctl --bare --columns="$2" find Chassis name="$1" 2>/dev/null | sed '/^$/d'; }
peer_encap_ip(){ timeout 30 ovn-sbctl --bare --columns=ip find Encap chassis_name="$PEER" 2>/dev/null | sed '/^$/d' | head -1; }
agent_alive_on() {   # agent_alive_on <host> <agent type>
    os_ network agent list --host "$1" -f value -c "Agent Type" -c Alive | grep -Fx "$2 True" >/dev/null
}
fip_ssh() {      # fip_ssh <floating ip> <command>
    ssh -i "$GUEST_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR "cirros@$1" "$2"
}
fip_of(){ awk -v n="$1" '$1 == n {print $2}' "$OUT/floating-ips.txt" 2>/dev/null | tail -1; }
fip_attach() {   # fip_attach <name> -> prints the floating IP
    local f; f="$(os_ floating ip create hagistack-provider -f value -c floating_ip_address)" || return 1
    os_ server add floating ip "$1" "$f" >/dev/null || return 1
    printf '%s %s\n' "$1" "$f" >> "$OUT/floating-ips.txt"; echo "$f"
}
cluster_guest() {   # cluster_guest <label> <name>: booted on the compute node, reached over its floating IP
    local l="$1" n="$2" ip f iid h
    ip="$(guest_boot "$n")"
    check "$l: guest $n ACTIVE on the tenant network (${ip:-no address})" [ -n "$ip" ]
    [ -n "$ip" ] || return 1
    h="$(host_of "$n")"
    check "$l: $n runs on the compute node ($h)" [ "$h" = "$PEER" ]
    f="$(fip_attach "$n")"
    check "$l: floating IP for $n (${f:-none})" [ -n "$f" ]
    [ -n "$f" ] || return 1
    check "$l: SSH to $n over its floating IP, with the metadata-injected key" wait_until 300 fip_ssh "$f" true
    iid="$(fip_ssh "$f" 'curl -s http://169.254.169.254/latest/meta-data/instance-id || wget -qO- http://169.254.169.254/latest/meta-data/instance-id' 2>/dev/null)"
    check "$l: $n reads its instance-id from the metadata service on the compute node ($iid)" is_instance_id "$iid"
}
fip_ping() {     # fip_ping <label> <from-name> <to-name>: guest to guest on the tenant network
    local l="$1" f t got
    f="$(fip_of "$2")"; t="$(guest_addr "$3")"
    [ -n "$f" ] && [ -n "$t" ] || { fail "$l: addresses for $2 -> $3 (${f:-none}, ${t:-none})"; return 0; }
    if wait_until 300 fip_ssh "$f" "ping -c 1 -W 2 $t"; then note "$l: $3 answered a first ping"
    else note "$l: $3 gave no first ping reply within 300 s"; fi
    mkdir -p -m 0700 "$OUT/diag"
    { fip_ssh "$f" "ping -c 5 $t" 2>&1; echo "==== exit $?"; } > "$OUT/diag/ping-$l.txt"
    got="$(ping_received "$OUT/diag/ping-$l.txt")"
    check "$l: $2 pings $3 (${got:-0}/5 received, at least 3 needed, after up to 300 s for a first reply)" [ "${got:-0}" -ge 3 ]
}
registration_checks() {   # registration_checks <label>
    local l="$1" gw
    check "$l: nova-compute on $PEER is up" wait_until 900 compute_up
    check "$l: $PEER is a hypervisor and up" wait_until 300 hypervisor_on_peer
    check "$l: no nova-compute on the controller" answers_empty compute service list --service nova-compute --host "$HOST" -f value -c State
    check "$l: Nova scheduler and conductor up" wait_until 300 services_up_ctrl
    check "$l: Placement lists a resource provider" wait_until 300 placement_ok
    check "$l: the OVN chassis are exactly $HOST and $PEER ($(chassis_set))" wait_until 300 chassis_pair
    gw="$(chassis_field "$HOST" other_config) $(chassis_field "$HOST" external_ids)"
    check "$l: the controller's chassis is the gateway chassis" grep -q 'enable-chassis-as-gw' <<<"$gw"
    gw="$(chassis_field "$PEER" other_config) $(chassis_field "$PEER" external_ids)"
    check "$l: the compute node's chassis is not a gateway" not grep -q 'enable-chassis-as-gw' <<<"$gw"
    local eip pip; eip="$(peer_encap_ip)"; pip="$(peer_ip)"
    check "$l: the compute node's Geneve endpoint is its own address (${eip:-none}, ${pip:-none})" [ -n "$eip" -a "$eip" = "$pip" ]
    check "$l: OVN Controller Gateway agent on $HOST alive" wait_until 300 agent_alive_on "$HOST" "OVN Controller Gateway agent"
    check "$l: OVN Controller agent on $PEER alive" wait_until 300 agent_alive_on "$PEER" "OVN Controller agent"
    check "$l: OVN Metadata agent on $PEER alive" wait_until 300 agent_alive_on "$PEER" "OVN Metadata agent"
}
answers_empty(){ local o; o="$(os_ "$@" 2>/dev/null)" || return 1; [ -z "$o" ]; }
services_up_ctrl() {
    local st; st="$(os_ compute service list -f value -c Binary -c State 2>/dev/null)" || return 1
    echo "$st" | grep -q '^nova-scheduler up$' && echo "$st" | grep -q '^nova-conductor up$'
}

# ---------------------------------------------------------- the handoff (n1 -> n2) --
HANDOFF_SERVER='
import hashlib, os, signal, socket, subprocess, sys
me, port, peer, path, res = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
rule = "rule family=ipv4 source address=%s/32 port port=%d protocol=tcp accept" % (peer, port)
def stop(*_):
    raise SystemExit(3)
signal.signal(signal.SIGTERM, stop)
def log(m):
    with open(res, "a") as f:
        f.write(m + "\n")
data = open(path, "rb").read()
digest = hashlib.sha256(data).hexdigest().encode()
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((me, port)); s.listen(1)
rc = 3
try:
    while True:
        c, (ip, _p) = s.accept()
        if ip != peer:
            log("REFUSED a connection from another address")
            c.close(); continue
        c.settimeout(600)
        c.sendall(b"%d\n" % len(data)); c.sendall(data)
        reply = b""
        while not reply.endswith(b"\n") and len(reply) < 200:
            chunk = c.recv(200)
            if not chunk:
                break
            reply += chunk
        ok = reply.strip() == digest
        c.sendall(b"MATCH\n" if ok else b"MISMATCH\n"); c.close()
        log("SENT %d bytes; the receiver\x27s SHA-256 %s" % (len(data), "matches" if ok else "does NOT match"))
        rc = 0 if ok else 1
        break
finally:
    s.close()
    try:
        subprocess.run(["shred", "-u", path], check=False)
    except OSError:
        pass
    if os.path.exists(path):
        os.remove(path)
    try:
        subprocess.run(["firewall-cmd", "--remove-rich-rule", rule], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass
    log("DONE rc=%d; the handoff file is deleted and the firewall rule removed" % rc)
sys.exit(rc)
'
HANDOFF_CLIENT='
import hashlib, socket, sys, time
host, port, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
end = time.time() + 600
while True:
    try:
        c = socket.create_connection((host, port), timeout=30); break
    except OSError:
        if time.time() > end:
            print("could not connect"); sys.exit(2)
        time.sleep(10)
c.settimeout(600)
f = c.makefile("rb")
n = int(f.readline())
h = hashlib.sha256(); got = 0
with open(path, "wb") as out:
    while got < n:
        chunk = f.read(min(1 << 20, n - got))
        if not chunk:
            break
        out.write(chunk); h.update(chunk); got += len(chunk)
if got != n:
    print("short transfer: %d of %d bytes" % (got, n)); sys.exit(1)
c.sendall(h.hexdigest().encode() + b"\n")
answer = f.readline().strip()
print("received %d bytes; the sender answered %s" % (got, answer.decode()))
sys.exit(0 if answer == b"MATCH" else 1)
'

# -------------------------------------------------------------- controller --
s_controller() {
    set_env
    [ ! -d "$OUT/install.started" ] || stop "this node ran the all-in-one install of s66-node.sh; a controller needs a fresh node"
    ip link show hgext0 >/dev/null 2>&1 || { ip link add hgext0 type dummy && ip link set hgext0 up; }
    check "dummy provider interface hgext0 is up (never attached to the outside)" link_up hgext0
    local t0 rc
    t0=$(date +%s)
    ( cd "$R" && ./hagistack controller --rpm-source build "${PROVIDER_ARGS[@]}" ) > "$OUT/controller.out" 2>&1; rc=$?
    tail -n 60 "$OUT/controller.out"
    check "hagistack controller exit 0 (rc=$rc, $(( $(date +%s) - t0 )) s)" [ "$rc" -eq 0 ]
    [ "$rc" -eq 0 ] || return 0
    check "the deployment records role controller" grep -qx "ROLE=controller" /etc/hagistack/deployment.env
    check "the deployment records the new set" grep -qx "RPM_SET_SHA256=$SET_ID" /etc/hagistack/deployment.env
    local bad n
    bad="$(installed_mismatch)"; n=$(wc -l < "$OUT/installed-set.tsv")
    check "$n installed packages are named in the set, each with the set's header${bad:+ (other: $bad)}" [ "$n" -gt 0 -a -z "$bad" ]
    local p
    for p in openstack-nova-compute libvirt qemu-kvm; do check "$p is not installed on the controller" not rpm -q "$p"; done

    # a controller with no compute node
    check "controller: Keystone issues a token" wait_until 120 token_ok
    check "controller: Nova API answers (flavor m1.tiny)" wait_until 120 flavor_ok
    check "controller: Nova scheduler and conductor up" wait_until 300 services_up_ctrl
    check "controller: Neutron API answers (hagistack-tenant)" wait_until 120 network_ok
    check "controller: Placement answers" wait_until 120 placement_answers
    check "controller: no nova-compute service is registered (the list call succeeds and is empty)" answers_empty compute service list --service nova-compute -f value -c Host
    check "controller: no hypervisor (the list call succeeds and is empty)" answers_empty hypervisor list -f value -c ID
    check "controller: one OVN chassis, this host ($(chassis_set))" [ "$(chassis_set)" = "$HOST" ]
    check "controller: system-id.conf holds the host name" [ "$(cat /etc/openvswitch/system-id.conf 2>/dev/null)" = "$HOST" ]
    check "controller: OVN Controller Gateway agent alive" wait_until 300 agent_alive_on "$HOST" "OVN Controller Gateway agent"
    local st fault
    os_ server create --image cirros-0.6.3-x86_64 --flavor m1.tiny --network hagistack-tenant s67-nohost -f value -c id >/dev/null 2>&1
    wait_until 300 nohost_error
    st="$(server_status s67-nohost 2>/dev/null)"
    fault="$(os_ server show s67-nohost -f value -c fault 2>/dev/null)"
    check "controller: a guest cannot be scheduled with no compute node (status $st, 'No valid host')" \
        bash -c '[ "$1" = ERROR ] && grep -q "No valid host" <<<"$2"' _ "$st" "$fault"
    os_ server delete --wait s67-nohost >/dev/null 2>&1
    check "controller: the unscheduled guest is deleted" not os_ server show s67-nohost
    local mtu nmtu pmtu
    mtu="$(nic_mtu "$(my_ip)")"; pmtu="$(crudini --get /etc/neutron/neutron.conf DEFAULT global_physnet_mtu 2>/dev/null)"
    nmtu="$(os_ network show hagistack-tenant -f value -c mtu)"
    check "controller: global_physnet_mtu is the management MTU ($pmtu, $mtu)" [ -n "$mtu" -a "$pmtu" = "$mtu" ]
    check "controller: the tenant network MTU leaves room for Geneve ($nmtu = $mtu - 58)" [ -n "$mtu" -a "$nmtu" = "$(( ${mtu:-0} - 58 ))" ]
    time_check

    # what README tells the operator to do on the controller, then the handoff:
    # offered only by a controller that passed every check above
    open_firewall "$CONTROLLER_PORTS" "6081"
    [ "$FAILS" -eq 0 ] || { note "the handoff is not offered: $FAILS check(s) failed above"; return 0; }
    umask 077
    rm -rf "$HANDOFF"; install -d -m 0700 "$HANDOFF"
    ( cd "$R" && ./hagistack compute-secrets ) > "$HANDOFF/secrets.env" 2> "$OUT/compute-secrets.err"; rc=$?
    check "hagistack compute-secrets exit 0 to a file (rc=$rc)" [ "$rc" -eq 0 ]
    check "compute-secrets holds exactly: $COMPUTE_SECRET_NAMES" [ "$(secret_names "$HANDOFF/secrets.env")" = "$COMPUTE_SECRET_NAMES" ]
    check "compute-secrets names the new set" grep -qx "RPM_SET_SHA256=$SET_ID" "$HANDOFF/secrets.env"
    ( cd "$R" && ./hagistack rpm-bundle --output "$HANDOFF/rpms.tar" ) > "$OUT/rpm-bundle.out" 2>&1; rc=$?
    check "hagistack rpm-bundle exit 0 and names the new set (rc=$rc)" bash -c '[ "$1" -eq 0 ] && grep -qx "RPM_SET_SHA256=$2" "$3"' _ "$rc" "$SET_ID" "$OUT/rpm-bundle.out"
    ( cd "$R" && ./hagistack rpm-bundle --output "$HANDOFF/rpms.tar" ) > "$OUT/rpm-bundle-again.out" 2>&1
    check "rpm-bundle refuses to overwrite its output" grep -q "refusing to overwrite" "$OUT/rpm-bundle-again.out"
    echo "$mtu" > "$HANDOFF/controller-mtu"
    if [ "$FAILS" -ne 0 ]; then
        shred -u "$HANDOFF/secrets.env"; rm -f "$HANDOFF/rpms.tar" "$HANDOFF/controller-mtu"
        note "the handoff is not offered: $FAILS check(s) failed above"; return 0
    fi
    tar -cf "$HANDOFF/handoff.tar" -C "$HANDOFF" secrets.env rpms.tar controller-mtu
    shred -u "$HANDOFF/secrets.env"; rm -f "$HANDOFF/rpms.tar" "$HANDOFF/controller-mtu"
    local me pip
    me="$(my_ip)"; pip="$(peer_ip)"
    check "the compute node's name resolves ($PEER -> ${pip:-nothing})" is_ipv4 "$pip"
    is_ipv4 "$pip" || return 0
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --add-rich-rule "rule family=ipv4 source address=$pip/32 port port=$HANDOFF_PORT protocol=tcp accept" >/dev/null
    fi
    : > "$OUT/handoff.result"
    systemd-run --unit="$HANDOFF_UNIT" --collect --quiet -p RuntimeMaxSec=3600 \
        /usr/bin/python3 -I -c "$HANDOFF_SERVER" "$me" "$HANDOFF_PORT" "$pip" "$HANDOFF/handoff.tar" "$OUT/handoff.result"
    sleep 2
    check "the handoff is offered once, on $me:$HANDOFF_PORT, to $PEER ($pip) only, for at most 1 h" \
        systemctl is-active --quiet "$HANDOFF_UNIT"
}
nohost_error(){ [ "$(server_status s67-nohost)" = ERROR ]; }
placement_answers() {
    ( set -a; . "$OPENRC"; set +a
      url="$(openstack endpoint list --service placement --interface public -f value -c URL | head -1)"
      tok="$(openstack token issue -f value -c id)"
      curl -sf -o /dev/null -H "X-Auth-Token: $tok" -H 'OpenStack-API-Version: placement 1.0' "$url/resource_providers" )
}

# ----------------------------------------------------------------- compute --
COMPUTE_UNITS="openstack-nova-compute ovn-controller openvswitch neutron-ovn-metadata-agent"
rerun_snapshot() {   # rerun_snapshot <file>: digests, kept off the evidence (some files hold credentials)
    local f
    ( umask 077
      for f in /etc/nova/nova.conf /etc/neutron/neutron_ovn_metadata_agent.ini /etc/openvswitch/system-id.conf \
               /etc/hagistack/deployment.env /etc/hagistack/secrets.env; do
          if [ -f "$f" ]; then printf '%s %s\n' "$(sha256sum < "$f" | cut -d' ' -f1)" "$f"; else echo "missing $f"; fi
      done
      printf '%s ovs-external-ids\n' "$(ovs-vsctl get open . external-ids 2>&1 | sha256sum | cut -d' ' -f1)"
      printf '%s ovs-manager\n' "$(ovs-vsctl get-manager 2>&1 | sha256sum | cut -d' ' -f1)" ) > "$1"
}
compute_add() {   # compute_add <output name>
    local pip; pip="$(peer_ip)"
    ( cd "$R" && ./hagistack compute-add --controller-ip "$pip" --rpm-source bundle --rpm-bundle "$HANDOFF/rpms.tar" ) \
        > "$OUT/$1" 2>&1
}
compute_local_checks() {   # compute_local_checks <label>
    local l="$1" pip me lines
    pip="$(peer_ip)"; me="$(my_ip)"
    check "$l: the deployment records role compute" grep -qx "ROLE=compute" /etc/hagistack/deployment.env
    check "$l: system-id.conf holds the host name" [ "$(cat /etc/openvswitch/system-id.conf 2>/dev/null)" = "$HOST" ]
    check "$l: OVS system-id is the host name" [ "$(ovs-vsctl get open . external-ids:system-id | tr -d '"')" = "$HOST" ]
    check "$l: ovn-remote is the controller's southbound DB (tcp:$pip:6642)" \
        [ "$(ovs-vsctl get open . external-ids:ovn-remote | tr -d '"')" = "tcp:$pip:6642" ]
    check "$l: ovn-encap-ip is this node's address ($me)" [ "$(ovs-vsctl get open . external-ids:ovn-encap-ip | tr -d '"')" = "$me" ]
    check "$l: no gateway or bridge mapping on the compute node" \
        not bash -c 'ovs-vsctl get open . external-ids | grep -qE "enable-chassis-as-gw|ovn-bridge-mappings"'
    lines="$(ini_active /etc/nova/nova.conf database 'connection|slave_connection') $(ini_active /etc/nova/nova.conf api_database 'connection|slave_connection')"
    check "$l: nova.conf has no active database connection (lines:${lines// /})" [ -z "${lines// /}" ]
    check "$l: /etc/hagistack/secrets.env holds no database or admin password" \
        not grep -qE '^(MYSQL_ROOT_PASS|[A-Z]+_DB_PASS|ADMIN_PASSWORD)=' /etc/hagistack/secrets.env
    check "$l: /etc/hagistack/secrets.env is root:root 0600" [ "$(stat -c '%U:%G %a' /etc/hagistack/secrets.env)" = "root:root 600" ]
    check "$l: there is no admin-openrc on the compute node" [ ! -e /etc/hagistack/admin-openrc ]
    check "$l: $COMPUTE_UNITS active" wait_until 120 units_active $COMPUTE_UNITS
    check "$l: libvirt active (libvirtd or virtqemud)" bash -c 'systemctl is-active --quiet libvirtd || systemctl is-active --quiet virtqemud'
}
s_compute() {
    local pip rc out
    pip="$(peer_ip)"
    check "the controller's name resolves ($PEER -> ${pip:-nothing})" is_ipv4 "$pip"
    is_ipv4 "$pip" || return 0
    open_firewall "" "6081"
    umask 077
    rm -rf "$HANDOFF"; install -d -m 0700 "$HANDOFF"
    out="$(python3 -I -c "$HANDOFF_CLIENT" "$pip" "$HANDOFF_PORT" "$HANDOFF/handoff.tar" 2>&1)"; rc=$?
    echo "$out"
    check "the handoff came from the controller and the sender confirmed its SHA-256 ($out)" [ "$rc" -eq 0 ]
    [ "$rc" -eq 0 ] || return 0
    tar -xf "$HANDOFF/handoff.tar" -C "$HANDOFF" --no-same-owner; shred -u "$HANDOFF/handoff.tar"
    check "the handoff holds compute-secrets, the RPM bundle and the controller's MTU" \
        [ -s "$HANDOFF/secrets.env" -a -s "$HANDOFF/rpms.tar" -a -s "$HANDOFF/controller-mtu" ]
    check "compute-secrets holds exactly: $COMPUTE_SECRET_NAMES" [ "$(secret_names "$HANDOFF/secrets.env")" = "$COMPUTE_SECRET_NAMES" ]
    local want; want="$(sed -n 's/^RPM_SET_SHA256=//p' "$HANDOFF/secrets.env")"
    # README step 3
    install -d -m 0700 /etc/hagistack
    install -o root -g root -m 0600 "$HANDOFF/secrets.env" /etc/hagistack/secrets.env && shred -u "$HANDOFF/secrets.env"
    check "the credentials are installed as README says and the copy is deleted" \
        [ -f /etc/hagistack/secrets.env -a ! -e "$HANDOFF/secrets.env" ]
    local mtu cmtu; mtu="$(nic_mtu "$(my_ip)")"; cmtu="$(cat "$HANDOFF/controller-mtu")"
    check "the management MTU is the controller's ($mtu, $cmtu)" [ -n "$mtu" -a "$mtu" = "$cmtu" ]
    time_check
    local t0; t0=$(date +%s)
    compute_add compute-add.out; rc=$?
    tail -n 60 "$OUT/compute-add.out"
    check "hagistack compute-add --controller-ip $pip --rpm-source bundle exit 0 (rc=$rc, $(( $(date +%s) - t0 )) s)" [ "$rc" -eq 0 ]
    [ "$rc" -eq 0 ] || return 0
    check "compute-add verified this node's set against the controller's" grep -q "this node's RPM set is the controller's" "$OUT/compute-add.out"
    check "the deployment records the controller's set" grep -qx "RPM_SET_SHA256=$want" /etc/hagistack/deployment.env
    SET_DIR="$(sed -n 's/^RPM_SET_DIR=//p' /etc/hagistack/deployment.env)"
    local bad n
    bad="$(installed_mismatch)"; n=$(wc -l < "$OUT/installed-set.tsv")
    check "$n installed packages are named in the set, each with the set's header${bad:+ (other: $bad)}" [ "$n" -gt 0 -a -z "$bad" ]
    local p
    for p in openstack-nova-api openstack-keystone mariadb-server rabbitmq-server openstack-dashboard; do
        check "$p is not installed on the compute node" not rpm -q "$p"
    done
    compute_local_checks compute
}
s_reboot() {
    check "nova-compute is active before the reboot" systemctl is-active --quiet openstack-nova-compute
    cat /proc/sys/kernel/random/boot_id > "$OUT/boot-id-before-reboot.txt"
    # not hs6-reboot: that is the name of this step's own unit
    systemd-run --unit="$REBOOT_UNIT" --collect --quiet --on-active=20 /usr/bin/systemctl reboot
    check "a reboot of this node is scheduled in 20 s" systemctl is-active --quiet "$REBOOT_UNIT.timer"
}
s_rerun() {
    local before after rc f t_back
    before="$(cat "$OUT/boot-id-before-reboot.txt" 2>/dev/null)"
    after="$(cat /proc/sys/kernel/random/boot_id)"
    check "this node has rebooted since the reboot step (the kernel boot id changed)" [ -n "$before" -a "$before" != "$after" ]
    compute_local_checks after-reboot
    rerun_snapshot "$BASE/rerun-before"
    local pids_b pids_a
    pids_b="$(for u in $COMPUTE_UNITS; do systemctl show -p MainPID --value "$u"; done | tr '\n' ' ')"
    compute_add compute-add-rerun.out; rc=$?
    tail -n 40 "$OUT/compute-add-rerun.out"
    check "compute-add re-run exit 0 (rc=$rc)" [ "$rc" -eq 0 ]
    check "the re-run re-used the verified set (nothing fetched)" grep -q "re-using the RPM set this host was deployed from" "$OUT/compute-add-rerun.out"
    rerun_snapshot "$BASE/rerun-after"
    local changed
    changed="$(join -j 2 <(sort -k2 "$BASE/rerun-before") <(sort -k2 "$BASE/rerun-after") | awk '$2 != $3 {printf " %s", $1}')"
    [ "$(wc -l < "$BASE/rerun-before")" -eq "$(join -j 2 <(sort -k2 "$BASE/rerun-before") <(sort -k2 "$BASE/rerun-after") | wc -l)" ] \
        || changed="$changed (an entry appeared or went)"
    check "the re-run changed no configuration (nova.conf, metadata agent, system-id.conf, deployment, secrets, OVS)${changed:+ — changed:$changed}" [ -z "$changed" ]
    compute_local_checks after-rerun
    # the window that is judged starts after the re-run, which may have restarted
    # units; what came before it (the reboot, the re-run) is counted, not judged
    note "Python tracebacks on the compute node between the boot and the end of the re-run: $(tracebacks_between "" "$(date +%s)")"
    t_back=$(date +%s)
    pids_a="$(for u in $COMPUTE_UNITS; do systemctl show -p MainPID --value "$u"; done | tr '\n' ' ')"
    [ "$pids_b" = "$pids_a" ] && note "the re-run restarted none of: $COMPUTE_UNITS" \
                              || note "main PIDs before / after the re-run: $pids_b / $pids_a"
    rm -f "$BASE/rerun-before" "$BASE/rerun-after"
    # this node's own journals since it came back from the reboot: at least two
    # minutes are watched; a traceback there is an error that persists
    local left=$(( t_back + 120 - $(date +%s) )) a
    [ "$left" -gt 0 ] && sleep "$left"
    a="$(tracebacks_between "$t_back" "")"
    check "no Python traceback on the compute node after the re-run ($a in $(( $(date +%s) - t_back )) s)" [ "$a" = 0 ]
}

# ---------------------------------------------------------------- cluster --
s_cluster() {
    set_env
    local rc
    ( cd "$R" && ./hagistack discover-hosts ) > "$OUT/discover-hosts.out" 2>&1; rc=$?
    check "hagistack discover-hosts exit 0 (rc=$rc)" [ "$rc" -eq 0 ]
    registration_checks before-restart
    # this host reaches the provider network (and the floating IPs) through br-ex
    ip addr show dev br-ex | grep -q ' 172\.24\.4\.1/24 ' || ip addr add 172.24.4.1/24 dev br-ex
    ip link set br-ex up
    check "this host has 172.24.4.1/24 on br-ex (the provider gateway, for the floating IPs)" \
        bash -c 'ip -o -4 addr show dev br-ex | grep -q " 172\.24\.4\.1/24 "'
    cluster_guest before-restart s67-g1
    cluster_guest before-restart s67-g2
    fip_ping before-restart s67-g1 s67-g2
    local f n; f="$(fip_of s67-g1)"
    n="$( { fip_ssh "$f" 'head -c 2000000 /dev/zero' 2>/dev/null; } | wc -c | tr -d ' ')"
    check "before-restart: a 2 MB stream from s67-g1 crosses the Geneve tunnel whole ($n bytes)" [ "$n" = 2000000 ]
    diag cluster-before-restart
    local units n2 u t_restart t_recovered; rc=0
    units="$(openstack_units)"; n2=$(echo "$units" | grep -c .)
    echo "$units" > "$OUT/restarted-units-controller.txt"
    t_restart=$(date +%s)
    for u in $units; do systemctl restart "$u" || rc=1; done
    check "restart of the controller's $n2 OpenStack, OVN and web units" [ "$rc" -eq 0 -a "$n2" -gt 0 ]
    sleep 30
    check "after-restart: Keystone issues a token" wait_until 120 token_ok
    registration_checks after-restart
    cluster_guest after-restart s67-g3
    fip_ping after-restart s67-g3 s67-g1
    t_recovered=$(date +%s)
    save_times T_RESTART="$t_restart" T_RECOVERED="$t_recovered"
    diag cluster-after-restart
    local left=$(( t_recovered + 120 - $(date +%s) ))
    [ "$left" -gt 0 ] && sleep "$left"
    traceback_windows "$t_restart" "$t_recovered" cluster
    save_times T_CLUSTER_END="$(date +%s)"
}
s_after_reboot() {
    # the reboot step returns 20 s before the node goes down: wait until it is
    # down (nova-compute down, or s67-g1 silent), so nothing below is answered
    # by the node as it was before the reboot
    check "after-reboot: the compute node went down (nova-compute down or s67-g1 silent)" wait_until 600 peer_gone
    registration_checks after-reboot
    # After a host reboot Nova may show a guest ACTIVE whose domain is off, and
    # keep its old power state, until its power-state sync (every 10 min). So the
    # guest itself is asked: one that does not answer over SSH is started when
    # SHUTOFF, hard-rebooted when ACTIVE (start is refused for ACTIVE). A guest
    # that answers is left alone.
    local g st f up
    for g in s67-g1 s67-g2 s67-g3; do
        st="$(server_status "$g")"; f="$(fip_of "$g")"
        if [ -n "$f" ] && fip_ssh "$f" true >/dev/null 2>&1; then note "after-reboot: $g was $st and answered"
        else
            note "after-reboot: $g was $st and did not answer"
            if [ "$st" = SHUTOFF ]; then os_ server start "$g" >/dev/null 2>&1
            elif [ "$st" = ACTIVE ]; then os_ server reboot --hard "$g" >/dev/null 2>&1; fi
        fi
        check "after-reboot: $g ACTIVE again" wait_until 600 server_active "$g"
        check "after-reboot: SSH to $g over its floating IP" wait_until 300 fip_ssh "$f" true
    done
    # the guests' own clocks show that their host went down: a guest that kept
    # running would have been up since before the cluster step ended
    up="$(fip_ssh "$(fip_of s67-g1)" 'cut -d. -f1 /proc/uptime' 2>/dev/null)"
    load_times
    check "after-reboot: s67-g1 has booted since the cluster step ended (up ${up:-?} s, $(( $(date +%s) - ${T_CLUSTER_END:-0} )) s since)" \
        bash -c '[[ "$1" =~ ^[0-9]+$ ]] && [ -n "$2" ] && [ "$1" -lt $(( $(date +%s) - $2 )) ]' _ "$up" "${T_CLUSTER_END:-}"
    fip_ping after-reboot s67-g1 s67-g2
    save_times T_AFTER_REBOOT="$(date +%s)"
    diag after-reboot
}
s_final() {
    set_env
    load_times
    registration_checks after-rerun
    cluster_guest after-rerun s67-g4
    fip_ping after-rerun s67-g4 s67-g1
    diag final
    check "0 failed units on the controller" [ "$(systemctl --failed --no-legend --plain | grep -c .)" -eq 0 ]
    local bad; bad="$(installed_mismatch)"
    check "the controller still has only the new set's packages" [ -z "$bad" ]
    # tracebacks since the compute node came back after its reboot; the window
    # of the controller restart was judged in the cluster step
    local t="${T_AFTER_REBOOT:-}" a
    [ -n "$t" ] || { fail "the after-reboot step recorded no time"; return 0; }
    a="$(tracebacks_between "$t" "")"
    check "final: no Python traceback on the controller since the compute node came back ($a in $(( $(date +%s) - t )) s)" [ "$a" -eq 0 ]
}

# --------------------------------------------------------------- evidence --
diag_compute() {
    local d="$OUT/diag" f u
    mkdir -p -m 0700 "$d"; f="$d/state-compute.txt"; : > "$f"
    dump "$f" timeout 30 ovs-vsctl show
    dump "$f" timeout 30 ovs-vsctl get open . external-ids
    dump "$f" ip -br addr
    dump "$f" ip -br link
    dump "$f" ip netns list
    dump "$f" firewall-cmd --list-all
    dump "$f" timedatectl
    dump "$f" journalctl --list-boots --no-pager
    for u in $COMPUTE_UNITS libvirtd virtqemud; do dump "$f" systemctl status --no-pager -l --lines=30 "$u.service"; done
    for u in $COMPUTE_UNITS libvirtd virtqemud; do
        dump "$d/journal-compute-$u.txt" timeout 60 journalctl --no-pager -o short-iso -n 3000 -u "$u.service"
    done
    note "Python tracebacks in this node's OpenStack and Neutron journals, this boot: $(tracebacks_between "" "") (by unit in diag/journal-compute-*)"
}
s_evidence_c() {
    EVIDENCE_NAME=evidence-cluster; s_evidence
}
s_evidence_n() {
    diag_compute
    EVIDENCE_NAME=evidence-compute; s_evidence
}

# ------------------------------------------------------- run and status --
fn_of(){ echo "s_${1//-/_}"; }
s67_run_step() {
    local step="$1" busy
    case " $STEPS " in *" $step "*) ;; *) echo "REFUSED: '$step' is not a step of this node ($HOST, role ${ROLE:-none}: $STEPS)"; return 2 ;; esac
    busy="$(running_units | grep -vx "$HANDOFF_UNIT.service")"
    [ -z "$busy" ] || { echo "STOP: a step is still running: $busy (use status)"; return 3; }
    [ ! -d "$OUT/$step.started" ] || { echo "REFUSED: step $step has already been started (use status)"; return 3; }
    systemd-run --unit="hs6-$step" --collect --wait --quiet --service-type=exec \
        --setenv=HOME=/root --setenv=LANG=C.UTF-8 /bin/bash "$S67_SELF" "$step"
    echo "---- $step: unit finished; its log ----"
    cat "$OUT/$step.log" 2>/dev/null
    [ -e "$OUT/$step.passed" ] && { echo "---- $step: PASSED ----"; return 0; }
    echo "---- $step: NOT PASSED ----"; return 1
}
s67_status() {
    local end=$(( $(date +%s) + 12600 )) s state
    while [ -n "$(running_units | grep -vx "$HANDOFF_UNIT.service")" ] && [ "$(date +%s)" -lt "$end" ]; do sleep 30; done
    echo "node $HOST, role ${ROLE:-none}"
    for s in $STEPS; do
        state="not started"
        [ -d "$OUT/$s.started" ] && state="started, not passed"
        [ -e "$OUT/$s.passed" ] && state="passed"
        printf '%-13s %s\n' "$s" "$state"
    done
    [ -f "$OUT/handoff.result" ] && { echo "---- handoff ----"; cat "$OUT/handoff.result"; }
    for s in $STEPS; do [ -f "$OUT/$s.result" ] && { echo "---- $s.result ----"; cat "$OUT/$s.result"; }; done
    return 0
}
s67_main() {
    [ -n "$ROLE" ] || { echo "STOP: $HOST is neither <run>-n1 nor <run>-n2"; exit 2; }
    case " $STEPS " in *" $STEP "*) ;; *) echo "STOP: '$STEP' is not a step of the $ROLE ($STEPS)"; exit 2; esac
    [ "$(id -u)" -eq 0 ] || { echo "STOP: run as root"; exit 2; }
    [ -d "$OUT" ] && [ -d "$R" ] || { echo "STOP: $OUT or $R is missing (run the extract step first)"; exit 2; }
    local first prev="" s
    first="${STEPS%% *}"
    for s in $STEPS; do [ "$s" = "$STEP" ] && break; prev="$s"; done
    case "$STEP" in
        evidence-c|evidence-n)
            [ -d "$OUT/$first.started" ] || { echo "STOP: $first has not started"; exit 3; } ;;
        controller)
            [ -e "$OUT/pack.passed" ] || { echo "STOP: s66-node.sh pack has not passed on this node"; exit 3; } ;;
        compute)
            [ -e "$OUT/preflight.passed" ] || { echo "STOP: s66-node.sh preflight has not passed on this node"; exit 3; }
            [ ! -d "$OUT/build.started" ] || { echo "STOP: this node built a set; the compute node installs the controller's"; exit 3; } ;;
        *)
            [ -e "$OUT/$prev.passed" ] || { echo "STOP: step $prev has not passed"; exit 3; } ;;
    esac
    if ! mkdir "$OUT/$STEP.started" 2>/dev/null; then
        echo "STOP: step $STEP has already been started on this node; a retry needs a new approval"; exit 3
    fi
    say "stage 6-6-R5 step $STEP on $HOST ($ROLE) at $(date -u +%FT%TZ)"
    "$(fn_of "$STEP")"
    say "step $STEP: $FAILS failed check(s)"
    [ "$FAILS" -eq 0 ] && touch "$OUT/$STEP.passed"
    [ "$FAILS" -eq 0 ]
}

case "$STEP" in
    run|status)
        [ "$(id -u)" -eq 0 ] || { echo "STOP: run as root"; exit 2; }
        [ -d "$OUT" ] || { echo "STOP: $OUT is missing (run the extract step first)"; exit 2; }
        if [ "$STEP" = run ]; then s67_run_step "${2:-}"; else s67_status; fi
        exit $? ;;
esac
case " $ALL_STEPS " in *" $STEP "*) ;; *) echo "usage: s67-cluster.sh {run STEP|status}, STEP one of: $ALL_STEPS"; exit 2 ;; esac
s67_main "$@" 2>&1 | tee -a "$OUT/$STEP.log"
exit "${PIPESTATUS[0]}"
