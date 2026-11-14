#!/bin/bash
# s66-node.sh — the fixed steps of stage 6-6 on node n1 (Rocky Linux 10.2 x86_64).
#
#   sudo bash /var/tmp/hs6/tree/acceptance/stage6/s66-node.sh run STEP
#   sudo bash /var/tmp/hs6/tree/acceptance/stage6/s66-node.sh status
#
# `run STEP` starts STEP as a transient system service (systemd-run, unit
# hs6-STEP), waits for it and prints its log; the step passed when it left
# out/STEP.passed. The service is not part of the ssh session, so a dropped
# connection, a timeout on the harness side or a restart of systemd-logind does
# not kill a step that runs for an hour. `status` waits until no hs6-* unit is
# running (at most 3.5 h) and prints every step's state and result: the way back
# after a dropped connection. Neither starts anything else.
#
# It is run only through `hs6.py ssh`, whose commands are fixed by
# acceptance/stage6/run-plan.json at the approved commit. This file reaches
# the node inside `git archive` of that same commit, so the approved commit
# fixes what runs here. Nothing here takes a parameter from the command line
# except the step name.
#
# Steps, in this order:
#   preflight  the node is a fresh Rocky Linux 10.2 x86_64 with KVM; record the tools
#   build      hagistack rpm-prepare --rpm-source build: a new set from the definitions
#   release    make-rpm-release.sh on the new set, twice; the two must be byte-identical
#   nodocs     notices and marks in a scratch root, with and without --excludedocs
#   pack       the candidate and the build evidence, for download (before any install)
#   install    hagistack all-in-one with the new set only
#   accept     APIs, Horizon, documentation, guests, restart
#   evidence   the final evidence, for download (runs after a failed install or accept too)
#
# Each step runs once: a second start of a step refuses (no retry without a new
# approval). Each step needs the step before it to have passed, except evidence,
# which runs once accept has started or once a step has failed, so the logs of
# an early failure can be fetched too. Only one step runs at a time. Output: /var/tmp/hs6/out/<step>.log and
# <step>.result (one PASS / FAIL / NOTE line per check). Exit 0 only when no
# check failed.
#
# Never written to the output or the evidence: /etc/hagistack (admin password,
# guest key) and tokens. For diagnosis, accept and evidence keep under out/diag/
# the state of agents, services, ports, OVN and OVS, the guests' console logs and
# the last lines of the journals of the Neutron, OVN, Nova and web units. Before
# packing, every diagnostic file is scanned like the rest of the evidence, and a
# file in which a secret value appears is withheld (only its name is listed).
# The evidence stays on the operator's machine; screen it before quoting it.
set -uo pipefail
umask 022
export LC_ALL=C

BASE=/var/tmp/hs6
TREE="$BASE/tree"
R="$TREE/rocky10.2"
OUT="$BASE/out"
DL=/var/tmp/hs6-dl
TAG="rocky10.2-rpms-2026.1-rc3"
OLD_SET="6c43da51144ca01c413f5c7dbbc44be70b66f03df69e77b3e632c2d55b8a1313"
EXPECT_SRPMS=69
OPENRC=/etc/hagistack/admin-openrc
GUEST_KEY=/etc/hagistack/hagistack-key
export OPENRC GUEST_KEY
MARK="# Hagistack: this file is changed from the upstream release; the changes are listed in HAGISTACK-CHANGES under /usr/share/hagistack/changes/."
STEPS="preflight build release nodocs pack install accept evidence"

STEP="${1:-}"
FAILS=0

pass(){ printf 'PASS  %s\n' "$*" | tee -a "$OUT/$STEP.result"; }
fail(){ printf 'FAIL  %s\n' "$*" | tee -a "$OUT/$STEP.result"; FAILS=$((FAILS + 1)); }
note(){ printf 'NOTE  %s\n' "$*" | tee -a "$OUT/$STEP.result"; }
check(){ local what="$1"; shift; if "$@"; then pass "$what"; else fail "$what"; fi; }
not(){ ! "$@"; }
stop(){ printf 'STOP  %s\n' "$*" | tee -a "$OUT/$STEP.result"; exit 1; }
say(){ printf '\n######## %s ########\n' "$*"; }

set_env(){ . "$OUT/set.env"; }   # SET_DIR SET_ID RPMS SRPMS (written by build)

# --------------------------------------------------------------- preflight --
s_preflight() {
    local id ver
    id="$(. /etc/os-release; echo "$ID")"; ver="$(. /etc/os-release; echo "$VERSION_ID")"
    check "OS is Rocky Linux 10.2 ($id $ver)" [ "$id" = rocky -a "$ver" = 10.2 ]
    check "architecture is x86_64 ($(uname -m))" [ "$(uname -m)" = x86_64 ]
    check "the CPU offers vmx (nested KVM)" grep -qw vmx /proc/cpuinfo
    local p have=""
    for p in openstack-nova-common openstack-dashboard python3-neutron openstack-keystone; do
        rpm -q "$p" >/dev/null 2>&1 && have="$have $p"
    done
    check "no OpenStack package is installed yet${have:+ (found:$have)}" [ -z "$have" ]
    check "/var/lib/hagistack does not exist yet" [ ! -e /var/lib/hagistack ]
    say "tools"
    {
        echo "kernel: $(uname -r)"
        echo "rpm: $(rpm -q rpm)"
        echo "gawk: $(rpm -q gawk)"
        echo "awk: $(awk --version 2>&1 | head -1)"
        echo "python3: $(python3 -V 2>&1)"
        echo "selinux: $(getenforce 2>/dev/null || echo unknown)"
        echo "%__docdir_path: $(rpm --eval '%{__docdir_path}')"
        echo "nproc: $(nproc)"
        echo "memory: $(free -g | awk '/^Mem:/{print $2" GiB"}')"
        echo "disk /var: $(df -h --output=avail /var | tail -1 | tr -d ' ') free"
        echo "tree.tar: $(sha256sum "$BASE/tree.tar" | cut -d' ' -f1)"
    } | tee "$OUT/tools.txt"
    rpm --eval '%{__docdir_path}' | tr ':' '\n' | grep -qx '/usr/share/doc' \
        && note "rpm marks files under /usr/share/doc as documentation (as expected)" \
        || note "rpm's %__docdir_path does not name /usr/share/doc"
    rpm --eval '%{__docdir_path}' | tr ':' '\n' | grep -q '^/usr/share/hagistack' \
        && fail "rpm's %__docdir_path names /usr/share/hagistack: notices would be documentation" \
        || pass "rpm's %__docdir_path does not cover /usr/share/hagistack"
}

# ------------------------------------------------------------------- build --
s_build() {
    local t0 rc out set_dir set_id
    t0=$(date +%s)
    out="$OUT/rpm-prepare.out"
    ( cd "$R" && ./hagistack rpm-prepare --rpm-source build ) > "$out" 2>&1; rc=$?
    tail -n 40 "$out"
    echo "rpm-prepare: rc=$rc in $(( $(date +%s) - t0 )) s"
    [ "$rc" -eq 0 ] || stop "hagistack rpm-prepare --rpm-source build exited $rc (see rpm-prepare.out)"
    set_dir="$(sed -n 's/^RPM_SET_DIR=//p' "$out" | tail -1)"
    set_id="$(sed -n 's/^RPM_SET_SHA256=//p' "$out" | tail -1)"
    [[ "$set_id" =~ ^[0-9a-f]{64}$ ]] && [ -d "$set_dir/repo" ] || stop "rpm-prepare did not name a set"
    pass "rpm-prepare built and verified a set in $(( $(date +%s) - t0 )) s"
    check "set identity is the SHA-256 of its RPM-SHA256SUMS" \
        [ "$(sha256sum "$set_dir/RPM-SHA256SUMS" | cut -d' ' -f1)" = "$set_id" ]
    check "the set is new, not the old set ${OLD_SET:0:12}…" [ "$set_id" != "$OLD_SET" ]
    local rpms srpms
    rpms=$(find "$set_dir/repo" -maxdepth 1 -name '*.rpm' | wc -l)
    srpms=$(find "$set_dir/srpms" -maxdepth 1 -name '*.src.rpm' | wc -l)
    check "$srpms SRPMs (expected $EXPECT_SRPMS)" [ "$srpms" -eq "$EXPECT_SRPMS" ]
    note "$rpms binary RPMs"
    note "build.ok: $(tr '\n' ' ' < "$set_dir/logs/build.ok")"
    printf 'SET_DIR=%q\nSET_ID=%q\nRPMS=%q\nSRPMS=%q\n' "$set_dir" "$set_id" "$rpms" "$srpms" > "$OUT/set.env"
    # RPM <-> SRPM: every binary names an SRPM of the set, every SRPM has a binary
    ( cd "$set_dir/repo" && for f in *.rpm; do
          printf '%s\t%s\t%s\n' "$f" "$(rpm -qp --qf '%{NAME}' "$f" 2>/dev/null)" "$(rpm -qp --qf '%{SOURCERPM}' "$f" 2>/dev/null)"
      done ) > "$OUT/rpm-srpm.tsv"
    local missing orphan
    missing="$(cut -f3 "$OUT/rpm-srpm.tsv" | sort -u | while read -r s; do [ -f "$set_dir/srpms/$s" ] || echo "$s"; done)"
    orphan="$(cd "$set_dir/srpms" && for s in *.src.rpm; do grep -qF $'\t'"$s" "$OUT/rpm-srpm.tsv" || echo "$s"; done)"
    check "every binary RPM's SOURCERPM is in srpms/${missing:+ (missing: $missing)}" [ -z "$missing" ]
    check "every SRPM has a binary RPM${orphan:+ (none for: $orphan)}" [ -z "$orphan" ]
}

# ----------------------------------------------------------------- release --
s_release() {
    set_env
    local rc
    ( cd "$R" && ./make-rpm-release.sh --set-dir "$SET_DIR" --tag "$TAG" --out "$BASE/release" ) \
        > "$OUT/make-rpm-release.1.out" 2>&1; rc=$?
    cat "$OUT/make-rpm-release.1.out"
    [ "$rc" -eq 0 ] || stop "make-rpm-release.sh exited $rc"
    pass "make-rpm-release.sh exit 0 ($(grep -c '^  ok ' "$OUT/make-rpm-release.1.out") ok lines)"
    ( cd "$R" && ./make-rpm-release.sh --set-dir "$SET_DIR" --tag "$TAG" --out "$BASE/release2" ) \
        > "$OUT/make-rpm-release.2.out" 2>&1; rc=$?
    check "second make-rpm-release.sh exit 0" [ "$rc" -eq 0 ]
    check "the two candidates are byte-identical" diff -r "$BASE/release" "$BASE/release2"
    local lock="$BASE/release/rpm-release.lock.candidate"
    check "candidate lock names the new set" grep -qx "RPM_SET_SHA256=$SET_ID" "$lock"
    check "candidate lock names $RPMS RPMs" grep -qx "RPM_COUNT=$RPMS" "$lock"
    check "candidate lock names tag $TAG" grep -qx "RELEASE_TAG=$TAG" "$lock"
    ( cd "$BASE/release" && sha256sum -c SHA256SUMS ) > "$OUT/release-sha256sums.out" 2>&1; rc=$?
    check "the candidate's SHA256SUMS verify" [ "$rc" -eq 0 ]
    ( cd "$BASE/release" && find . -type f -printf '%P\n' | sort ) > "$OUT/release-files.txt"
    note "candidate files: $(tr '\n' ' ' < "$OUT/release-files.txt")"
}

# ------------------------------------------------------------------ nodocs --
s_nodocs() {
    set_env
    local repo="$SET_DIR/repo" f list="$OUT/notice-rpms.txt" flags="$OUT/notice-flags.tsv"
    : > "$list"; : > "$flags"
    for f in "$repo"/*.rpm; do
        rpm -qp --qf '[%{FILENAMES}\t%{FILEFLAGS:fflags}\n]' "$f" 2>/dev/null \
            | awk -F'\t' -v r="$(basename "$f")" '$1 ~ /^\/usr\/share\/hagistack\/changes\/[^\/]+\/HAGISTACK-CHANGES$/ {print r"\t"$1"\t"$2}' >> "$flags"
    done
    cut -f1 "$flags" | sort -u > "$list"
    local n dup docflag
    n=$(wc -l < "$list")
    dup="$(cut -f1 "$flags" | sort | uniq -d)"
    docflag="$(awk -F'\t' '$3 ~ /d/' "$flags")"
    check "$n RPMs carry a notice; none carries two${dup:+ (two: $dup)}" [ "$n" -gt 0 -a -z "$dup" ]
    check "no notice has the documentation flag${docflag:+ ($docflag)}" [ -z "$docflag" ]
    # install the notice RPMs and the documentation RPMs into two scratch roots
    local docs pkgs r1="$BASE/root-nodocs" r2="$BASE/root-docs"
    docs="$(cd "$repo" && for f in *.rpm; do [[ "$(rpm -qp --qf '%{NAME}' "$f" 2>/dev/null)" == *-doc ]] && echo "$f"; done)"
    pkgs="$( { cat "$list"; printf '%s\n' "$docs"; } | grep . | sort -u)"
    note "$(echo "$pkgs" | wc -l) RPMs installed into each scratch root ($(echo "$docs" | grep -c .) documentation RPMs)"
    local root opt rc
    for root in "$r1" "$r2"; do
        opt=""; [ "$root" = "$r1" ] && opt="--excludedocs"
        mkdir -p "$root/etc"; rpm --root "$root" --initdb
        # the packages' users and groups are created in the scratch root (sysusers):
        # give it the host's account files, so that works as on a real system
        cp -p /etc/passwd /etc/group /etc/shadow /etc/gshadow /etc/login.defs "$root/etc/" 2>/dev/null
        ( cd "$repo" && echo "$pkgs" | xargs -r rpm --root "$root" -i --nodeps --noscripts --notriggers --noplugins $opt ) \
            > "$OUT/nodocs-install-$(basename "$root").out" 2>&1; rc=$?
        check "rpm -i ${opt:-(with docs)} into $(basename "$root") exit 0" [ "$rc" -eq 0 ]
    done
    # every notice is at its path in both roots, byte-identical; no docs in the nodocs root
    local miss1="" miss2="" path
    while IFS=$'\t' read -r _ path _; do
        [ -f "$r1$path" ] || miss1="$miss1 $path"
        [ -f "$r2$path" ] || miss2="$miss2 $path"
    done < "$flags"
    check "--excludedocs keeps every notice${miss1:+ (missing:$miss1)}" [ -z "$miss1" ]
    check "a normal install has every notice${miss2:+ (missing:$miss2)}" [ -z "$miss2" ]
    check "the notices are the same with and without docs" \
        [ "$(cd "$r1" && find usr/share/hagistack -type f -exec sha256sum {} + | sort)" = \
          "$(cd "$r2" && find usr/share/hagistack -type f -exec sha256sum {} + | sort)" ]
    local d1 d2
    d1=$(find "$r1/usr/share/doc" -type f 2>/dev/null | wc -l)
    d2=$(find "$r2/usr/share/doc" -type f 2>/dev/null | wc -l)
    check "--excludedocs installed no file under /usr/share/doc ($d1)" [ "$d1" -eq 0 ]
    check "the normal install has documentation files ($d2), so the exclusion was exercised" [ "$d2" -gt 0 ]
    local l1 l2
    l1=$(find "$r1/usr/share/licenses" -name HAGISTACK-LICENSE -type f 2>/dev/null | wc -l)
    l2=$(find "$r2/usr/share/licenses" -name HAGISTACK-LICENSE -type f 2>/dev/null | wc -l)
    check "HAGISTACK-LICENSE kept under --excludedocs ($l1 of $l2)" [ "$l1" -gt 0 -a "$l1" -eq "$l2" ]
    # in-file marks: present, the same in both roots apart from documentation
    # (a marked file installed as %doc, such as placement's policy.yaml.sample,
    # is rightly absent with --excludedocs), and the files still parse
    local m1 m2 m2docs bad=""
    m1="$(cd "$r1" && grep -rlxF -- "$MARK" usr etc 2>/dev/null | sort)"
    m2="$(cd "$r2" && grep -rlxF -- "$MARK" usr etc 2>/dev/null | sort)"
    m2docs="$(printf '%s\n' "$m2" | grep '^usr/share/doc/')"
    printf '%s\n' "$m1" > "$OUT/marked-files.txt"
    printf '%s\n' "$m2docs" > "$OUT/marked-doc-files.txt"
    check "$(echo "$m1" | grep -c .) installed files carry the mark, the same with and without docs (plus $(echo "$m2docs" | grep -c .) marked documentation files only with docs)" \
        [ -n "$m1" -a "$m1" = "$(printf '%s\n' "$m2" | grep -v '^usr/share/doc/')" ]
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in
            *.py) python3 -I -c 'import sys; compile(open(sys.argv[1], "rb").read(), sys.argv[1], "exec")' "$r1/$f" \
                      2>>"$OUT/marked-parse.err" || bad="$bad $f" ;;
            *.sh) bash -n "$r1/$f" 2>>"$OUT/marked-parse.err" || bad="$bad $f" ;;
        esac
        # a shebang stays on line 1: the mark is never line 1 of a file that has one
        if [ "$(sed -n 1p "$r1/$f")" = "$MARK" ] && sed -n 2p "$r1/$f" | grep -q '^#!'; then bad="$bad $f(shebang)"; fi
    done <<< "$m1"
    check "marked .py files compile, marked .sh files parse, shebangs stay first${bad:+ (bad:$bad)}" [ -z "$bad" ]
}

# -------------------------------------------------------------------- pack --
s_pack() {
    set_env
    install -d -m 0755 "$DL"
    tar -cf "$DL/candidate.tar" -C "$BASE" release
    check "candidate.tar written" [ -s "$DL/candidate.tar" ]
    local ev="$BASE/evidence-build"
    rm -rf "$ev"; mkdir -p "$ev/set" "$ev/out"
    cp -p "$SET_DIR/RPM-SHA256SUMS" "$SET_DIR/build-env.lock" "$ev/set/"
    cp -rp "$SET_DIR/logs" "$ev/set/logs"
    [ -f "$SET_DIR/../container.log" ] && cp -p "$SET_DIR/../container.log" "$ev/set/"
    ( cd "$SET_DIR/repo" && for f in *.rpm; do rpm -qp --qf '%{NEVRA}\t%{SOURCERPM}\t%{BUILDHOST}\t%{SHA256HEADER}\n' "$f"; done ) \
        > "$ev/set/rpm-headers.tsv" 2>/dev/null
    cp -p "$OUT"/*.result "$OUT"/*.log "$OUT"/*.out "$OUT"/*.txt "$OUT"/*.tsv "$OUT/set.env" "$ev/out/" 2>/dev/null
    tar -cf "$DL/evidence-build.tar" -C "$BASE" evidence-build
    check "evidence-build.tar written" [ -s "$DL/evidence-build.tar" ]
    chmod 0644 "$DL"/*.tar
    ( cd "$DL" && sha256sum candidate.tar evidence-build.tar ) | tee "$OUT/download-sha256.txt"
    ls -l "$DL"
}

# ----------------------------------------------------------------- install --
link_up(){ ip -o link show "$1" 2>/dev/null | grep '[<,]UP[,>]' >/dev/null; }
installed_mismatch() {   # installed packages named in the set whose header is not the set's
    local f
    ( cd "$SET_DIR/repo" && for f in *.rpm; do rpm -qp --qf '%{NAME}\t%{SHA256HEADER}\n' "$f"; done ) 2>/dev/null \
        | sort -t $'\t' -k1,1 > "$OUT/set-headers.tsv"
    rpm -qa --qf '%{NAME}\t%{SHA256HEADER}\n' | sort -t $'\t' -k1,1 > "$OUT/installed-headers.tsv"
    join -t $'\t' "$OUT/set-headers.tsv" "$OUT/installed-headers.tsv" > "$OUT/installed-set.tsv"
    awk -F'\t' '$2 != $3 {print $1}' "$OUT/installed-set.tsv"
}

s_install() {
    set_env
    ip link show hgext0 >/dev/null 2>&1 || { ip link add hgext0 type dummy && ip link set hgext0 up; }
    check "dummy provider interface hgext0 is up (never attached to the outside)" link_up hgext0
    local t0 rc
    t0=$(date +%s)
    ( cd "$R" && ./hagistack all-in-one --rpm-source build --ext-nic hgext0 \
          --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1 \
          --floating-start 172.24.4.100 --floating-end 172.24.4.200 ) > "$OUT/all-in-one.out" 2>&1; rc=$?
    tail -n 60 "$OUT/all-in-one.out"
    check "hagistack all-in-one exit 0 (rc=$rc, $(( $(date +%s) - t0 )) s)" [ "$rc" -eq 0 ]
    check "the deployment records the new set" grep -qx "RPM_SET_SHA256=$SET_ID" /etc/hagistack/deployment.env
    check "the deployment does not record the old set" not grep -q "$OLD_SET" /etc/hagistack/deployment.env
    local bad n
    bad="$(installed_mismatch)"
    n=$(wc -l < "$OUT/installed-set.tsv")
    check "$n installed packages are named in the set, each with the set's header${bad:+ (other: $bad)}" \
        [ "$n" -gt 0 -a -z "$bad" ]
    check "novnc is not installed" not rpm -q novnc
    check "openstack-nova-novncproxy is not installed" not rpm -q openstack-nova-novncproxy
}

# ------------------------------------------------------------------ accept --
os_(){ ( set -a; . "$OPENRC"; set +a; openstack "$@" ); }

wait_until() {   # wait_until <seconds> <command...>
    local end=$(( $(date +%s) + $1 )); shift
    until "$@" >/dev/null 2>&1; do [ "$(date +%s)" -lt "$end" ] || return 1; sleep 10; done
}

token_ok(){ os_ token issue -f value -c expires >/dev/null; }
flavor_ok(){ os_ flavor show m1.tiny -f value -c name | grep -qx m1.tiny; }
network_ok(){ os_ network show hagistack-tenant -f value -c name | grep -qx hagistack-tenant; }
hypervisor_ok(){ os_ hypervisor list -f value -c State | grep -qx up; }
server_active(){ os_ server show "$1" -f value -c status | grep -qx ACTIVE; }
is_instance_id(){ [[ "$1" =~ ^i-[0-9a-f]+$ ]]; }
services_up() {
    local st
    st="$(os_ compute service list -f value -c Binary -c State 2>/dev/null)" || return 1
    for b in nova-scheduler nova-conductor nova-compute; do echo "$st" | grep -q "^$b up$" || return 1; done
    ! echo "$st" | grep -q ' down$'
}
agents_alive() {
    local a; a="$(os_ network agent list -f value -c Alive 2>/dev/null)" || return 1
    [ "$(echo "$a" | grep -c .)" -ge 2 ] && ! echo "$a" | grep -qv '^True$'
}
api_checks() {   # api_checks <label>
    local l="$1"
    check "$l: Keystone issues a token" wait_until 120 token_ok
    check "$l: Nova API answers (flavor m1.tiny)" wait_until 120 flavor_ok
    check "$l: Nova scheduler, conductor and compute up" wait_until 300 services_up
    check "$l: Neutron API answers (hagistack-tenant)" wait_until 120 network_ok
    check "$l: Neutron agents alive" wait_until 300 agents_alive
    check "$l: Placement lists a resource provider" wait_until 120 placement_ok
    check "$l: a hypervisor is up" wait_until 120 hypervisor_ok
}
placement_ok() {
    ( set -a; . "$OPENRC"; set +a
      url="$(openstack endpoint list --service placement --interface public -f value -c URL | head -1)"
      tok="$(openstack token issue -f value -c id)"
      curl -sf -H "X-Auth-Token: $tok" -H 'OpenStack-API-Version: placement 1.0' "$url/resource_providers" \
          | python3 -I -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["resource_providers"] else 1)' )
}

guest_boot() {   # guest_boot <name>  -> prints the guest's tenant address
    os_ server create --image cirros-0.6.3-x86_64 --flavor m1.tiny --network hagistack-tenant \
        --key-name hagistack-key "$1" -f value -c id >/dev/null || return 1
    wait_until 600 server_active "$1" || return 1
    os_ server show "$1" -f json -c addresses | python3 -I -c '
import json, sys
a = json.load(sys.stdin)["addresses"]
ips = a.get("hagistack-tenant") if isinstance(a, dict) else None
if isinstance(ips, str):
    ips = [ips]
print(ips[0])'
}
guest_ssh() {    # guest_ssh <ip> <command>
    local ns; ns="ovnmeta-$(os_ network show hagistack-tenant -f value -c id)"
    ip netns exec "$ns" ssh -i "$GUEST_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR "cirros@$1" "$2"
}
guest_checks() {  # guest_checks <label> <name> [<name2>]
    local l="$1" ip1 ip2 iid
    ip1="$(guest_boot "$2")"
    check "$l: guest $2 ACTIVE on the tenant network (${ip1:-no address})" [ -n "$ip1" ]
    [ -n "$ip1" ] || return 0
    check "$l: SSH to $2 with the metadata-injected key" wait_until 300 guest_ssh "$ip1" true
    iid="$(guest_ssh "$ip1" 'curl -s http://169.254.169.254/latest/meta-data/instance-id || wget -qO- http://169.254.169.254/latest/meta-data/instance-id' 2>/dev/null)"
    check "$l: $2 reads its instance-id from the metadata service ($iid)" is_instance_id "$iid"
    if [ -n "${3:-}" ]; then
        ip2="$(guest_boot "$3")"
        check "$l: guest $3 ACTIVE (${ip2:-no address})" [ -n "$ip2" ]
        if [ -n "$ip2" ]; then
            local got
            # ACTIVE is not booted: give $3 up to 300 s to answer a first ping, as the
            # SSH check gives $2, then count 5
            wait_until 300 guest_ssh "$ip1" "ping -c 1 -W 2 $ip2"
            got="$(guest_ssh "$ip1" "ping -c 5 $ip2" 2>/dev/null | sed -n 's/.* \([0-9]*\) packets received.*/\1/p')"
            check "$l: $2 pings $3 (${got:-0}/5 received, at least 3 needed, after up to 300 s for a first reply)" [ "${got:-0}" -ge 3 ]
        fi
    fi
}

# ------------------------------------------------------------- diagnostics --
# State kept for diagnosis off the node, never judged here. Every command is
# bounded by a timeout. Files go to $OUT/diag/; s_evidence withholds any of them
# in which a secret value appears.
DIAG_UNITS="neutron-rpc-server neutron-periodic-workers neutron-ovn-maintenance-worker neutron-ovn-metadata-agent ovn-controller ovn-northd ovsdb-server openvswitch openstack-nova-compute openstack-nova-conductor httpd"
os_t(){ ( set -a; . "$OPENRC"; set +a; timeout 60 openstack "$@" ); }
dump(){ local f="$1" rc; shift; { printf '\n==== %s\n' "$*"; "$@" 2>&1; rc=$?; printf '==== exit %s\n' "$rc"; } >> "$f"; }
diag() {         # diag <label>
    local d="$OUT/diag" f g u
    mkdir -p "$d"; f="$d/state-$1.txt"; : > "$f"
    dump "$f" os_t network agent list --long
    dump "$f" os_t compute service list
    dump "$f" os_t server list --long
    dump "$f" os_t port list --long
    dump "$f" os_t security group rule list --long
    dump "$f" timeout 30 ovn-nbctl show
    dump "$f" timeout 30 ovn-sbctl show
    dump "$f" timeout 30 ovs-vsctl show
    dump "$f" ip netns list
    dump "$f" ip -br addr
    for u in $DIAG_UNITS; do dump "$f" systemctl status --no-pager -l --lines=30 "$u.service"; done
    for g in $(os_t server list -f value -c Name 2>/dev/null); do
        dump "$d/console-$1-$g.txt" os_t console log show --lines 200 "$g"
    done
    for u in $DIAG_UNITS; do
        timeout 60 journalctl -b --no-pager -o short-iso -u "$u.service" 2>&1 | tail -n 3000 > "$d/journal-$1-$u.txt"
    done
}
asset_diag() {   # where the assets that returned HTTP 404 are, if anywhere, and their owners
    local f="$OUT/diag/assets-404.txt" url b p
    mkdir -p "$OUT/diag"; : > "$f"
    for url in $(grep -ho 'http://127\.0\.0\.1[^ ]* returned HTTP 404' "$OUT"/horizon-web.*.out "$OUT"/docs-web.out 2>/dev/null \
                 | awk '{print $1}' | sort -u); do
        b="${url##*/}"
        printf '\n==== %s\n' "$url" >> "$f"
        for p in $(timeout 120 find /usr/share /usr/lib/python3*/site-packages /usr/lib64/python3*/site-packages \
                       -name "$b" 2>/dev/null | head -20); do
            printf '%s\t%s\n' "$p" "$(rpm -qf "$p" 2>&1)" >> "$f"
        done
    done
}

web_checks() {   # web_checks <label>
    local l="$1" rc
    bash "$R/tests-horizon-login.sh" > "$OUT/horizon-login.$l.out" 2>&1; rc=$?
    check "$l: tests-horizon-login.sh (admin sign-in, protected pages, negative cases) exit 0" [ "$rc" -eq 0 ]
    python3 -I "$TREE/acceptance/stage6/s66_web.py" horizon --base http://127.0.0.1/dashboard \
        --openrc "$OPENRC" --images "$R/packaging/files/python-django-horizon" > "$OUT/horizon-web.$l.out" 2>&1; rc=$?
    sed 's/^/    /' "$OUT/horizon-web.$l.out"
    check "$l: Horizon admin pages, Hagistack logos, every image and asset loads (s66_web.py)" [ "$rc" -eq 0 ]
}

docs_check() {
    # one documentation package of the new set, installed from the set and served over HTTP
    set_env
    local f="" name html rc pid
    for f in "$SET_DIR"/repo/*.rpm; do
        name="$(rpm -qp --qf '%{NAME}' "$f" 2>/dev/null)"
        # grep reads all of the list (not -q): under pipefail an early exit would fail rpm with SIGPIPE
        [[ "$name" == *-doc ]] && rpm -qlp "$f" 2>/dev/null | grep '/html/index.html$' >/dev/null && break
        f=""
    done
    check "a documentation RPM with an HTML tree is in the set (${f##*/})" [ -n "$f" ]
    [ -n "$f" ] || return 0
    # tsflags cleared: an image whose dnf.conf says nodocs would leave the HTML out
    dnf -y --setopt=install_weak_deps=False --setopt=tsflags= install "$f" > "$OUT/doc-install.out" 2>&1; rc=$?
    check "dnf installs ${f##*/} from the set (exit $rc)" [ "$rc" -eq 0 ]
    html="$(rpm -qlp "$f" | grep '/html/index.html$' | awk '{print length, $0}' | sort -n | head -1 | cut -d' ' -f2-)"
    check "its index page is installed ($html)" [ -f "$html" ]
    [ -f "$html" ] || return 0
    html="${html%/index.html}"
    python3 -I -m http.server --bind 127.0.0.1 --directory "$html" 8999 > "$OUT/doc-http.log" 2>&1 & pid=$!
    sleep 2
    python3 -I "$TREE/acceptance/stage6/s66_web.py" docs --base http://127.0.0.1:8999 \
        --images "$R/packaging/files/_docs-branding" > "$OUT/docs-web.out" 2>&1; rc=$?
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    sed 's/^/    /' "$OUT/docs-web.out"
    check "documentation page ($html) shows Hagistack's logo and every image loads (s66_web.py)" [ "$rc" -eq 0 ]
}

openstack_units() {
    systemctl list-units --type=service --state=active --no-legend --plain \
        'openstack-*' 'neutron-*' 'ovn-*' 'ovsdb-server*' 'openvswitch*' 'httpd*' 'libvirtd*' 'virtqemud*' 2>/dev/null \
        | awk '{print $1}' | sort -u
}

s_accept() {
    set_env
    api_checks before-restart
    web_checks before-restart
    docs_check
    guest_checks before-restart s66-g1 s66-g2
    diag before-restart
    local units n rc=0 u
    units="$(openstack_units)"; n=$(echo "$units" | grep -c .)
    echo "$units" > "$OUT/restarted-units.txt"
    for u in $units; do systemctl restart "$u" || rc=1; done
    check "restart of $n OpenStack, OVN and web units" [ "$rc" -eq 0 -a "$n" -gt 0 ]
    sleep 30
    api_checks after-restart
    web_checks after-restart
    guest_checks after-restart s66-g3
    diag after-restart
    asset_diag
    check "0 failed units" [ "$(systemctl --failed --no-legend --plain | grep -c .)" -eq 0 ]
    local bad; bad="$(installed_mismatch)"
    check "still only the new set's packages (header check, after the documentation install)" [ -z "$bad" ]
    local tb; tb=$(journalctl -b --no-pager -o cat -u 'openstack-*' -u 'neutron-*' 2>/dev/null | grep -c '^Traceback')
    note "$tb Python tracebacks in the OpenStack and Neutron journals since boot (examined off the node only by count)"
}

# ---------------------------------------------------------------- evidence --
s_evidence() {
    local ev="$BASE/evidence-final" d f
    rm -rf "$ev"; mkdir -p "$ev/build"
    cp -p "$OUT"/*.result "$OUT"/*.log "$OUT"/*.out "$OUT"/*.txt "$OUT"/*.tsv "$ev/" 2>/dev/null
    [ -f "$OUT/set.env" ] && cp -p "$OUT/set.env" "$ev/"
    # the build's own logs, also after a failed build
    for d in /var/lib/hagistack/rpm-build/*/; do
        [ -d "$d" ] || continue
        mkdir -p "$ev/build/$(basename "$d")"
        [ -f "$d/container.log" ] && cp -p "$d/container.log" "$ev/build/$(basename "$d")/"
        [ -d "$d/out/logs" ] && cp -rp "$d/out/logs" "$ev/build/$(basename "$d")/logs"
        for f in RPM-SHA256SUMS build-env.lock; do [ -f "$d/out/$f" ] && cp -p "$d/out/$f" "$ev/build/$(basename "$d")/"; done
    done
    [ -d "$BASE/release" ] && ( cd "$BASE/release" && find . -type f -printf '%P\n' | sort | xargs -r sha256sum ) > "$ev/release-sha256.txt"
    ( cd "$R" && ./hagistack status ) > "$ev/hagistack-status.txt" 2>&1
    rpm -qa --qf '%{NEVRA}\t%{SHA256HEADER}\n' | sort > "$ev/rpm-qa.tsv"
    systemctl --failed --no-legend --plain > "$ev/failed-units.txt" 2>&1
    systemctl list-units --type=service --no-legend --plain > "$ev/units.txt" 2>&1
    # diagnostics: the state now, then every diagnostic file without a secret in it
    [ -f "$OPENRC" ] && [ -d "$OUT/accept.started" ] && diag at-evidence
    if [ -d "$OUT/diag" ]; then
        local hit nw=0
        cp -rp "$OUT/diag" "$ev/diag"
        python3 -I -c "$SECRET_SCAN" "$ev/diag" > "$OUT/diag-secret-hits.txt" 2>/dev/null
        while IFS= read -r hit; do
            [ -n "$hit" ] && rm -f -- "$ev/diag/$hit" && nw=$((nw + 1))
        done < "$OUT/diag-secret-hits.txt"
        cp "$OUT/diag-secret-hits.txt" "$ev/diag/WITHHELD.txt"   # file names only
        note "$(find "$ev/diag" -type f | wc -l) diagnostic files kept; $nw withheld because a secret value appears in them"
    fi
    # The evidence must carry no secret: every password, secret, token or key value
    # in /etc/hagistack and Horizon's secret key are looked for (never printed),
    # and so are private keys and Keystone tokens. A hit packs nothing.
    if ! python3 -I -c "$SECRET_SCAN" "$ev" > "$OUT/evidence-secret-hits.txt"; then
        stop "a secret appears in the evidence (files: $(tr '\n' ' ' < "$OUT/evidence-secret-hits.txt")): nothing is packed"
    fi
    pass "the evidence holds no password, secret, private key or token"
    install -d -m 0755 "$DL"
    tar -cf "$DL/evidence-final.tar" -C "$BASE" evidence-final
    chmod 0644 "$DL/evidence-final.tar"
    check "evidence-final.tar written" [ -s "$DL/evidence-final.tar" ]
    ( cd "$DL" && sha256sum evidence-final.tar ) | tee -a "$OUT/download-sha256.txt"
}

SECRET_SCAN='
import os, re, sys
ev = sys.argv[1]
etc = sys.argv[2] if len(sys.argv) > 2 else "/etc/hagistack"
vals = set()
for d, _s, files in os.walk(etc):
    for n in files:
        try:
            text = open(os.path.join(d, n), errors="replace").read()
        except OSError:
            continue
        for m in re.finditer(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", text, re.M):
            k, v = m.group(1), m.group(2).strip().strip("\x27\x22")
            if re.search(r"PASS|SECRET|TOKEN|KEY", k) and not k.endswith("SHA256") and len(v) >= 8:
                vals.add(v.encode())
for f in ("/etc/openstack-dashboard/.secret_key_store", "/var/lib/openstack-dashboard/secret_key"):
    try:
        v = open(f, "rb").read().strip()
    except OSError:
        continue
    if len(v) >= 8:
        vals.add(v)
pat = re.compile(rb"-----BEGIN [A-Z ]*PRIVATE KEY-----|gAAAA[A-Za-z0-9_-]{60,}")
hits = 0
for d, _s, files in os.walk(ev):
    for n in files:
        p = os.path.join(d, n)
        data = open(p, "rb").read()
        if pat.search(data) or any(v in data for v in vals):
            print(os.path.relpath(p, ev))
            hits += 1
sys.stderr.write("%d secret values looked for\n" % len(vals))
sys.exit(1 if hits else 0)
'

# ------------------------------------------------------- run and status --
running_units(){ systemctl list-units --all --no-legend --plain 'hs6-*' 2>/dev/null | awk '$3 == "active" || $4 == "running" {print $1}'; }

run_step() {     # run_step STEP: one step as a transient service, then its log
    local step="$1" self busy
    case " $STEPS " in *" $step "*) ;; *) echo "usage: s66-node.sh run {${STEPS// /|}}"; return 2 ;; esac
    busy="$(running_units)"
    [ -z "$busy" ] || { echo "STOP: a stage 6-6 step is still running: $busy (use status)"; return 3; }
    [ ! -d "$OUT/$step.started" ] || { echo "REFUSED: step $step has already been started (use status)"; return 3; }
    self="$(readlink -f "$0")"
    systemd-run --unit="hs6-$step" --collect --wait --quiet --service-type=exec \
        --setenv=HOME=/root --setenv=LANG=C.UTF-8 /bin/bash "$self" "$step"
    echo "---- $step: unit finished; its log ----"
    cat "$OUT/$step.log" 2>/dev/null
    [ -e "$OUT/$step.passed" ] && { echo "---- $step: PASSED ----"; return 0; }
    echo "---- $step: NOT PASSED ----"; return 1
}

show_status() {
    local end=$(( $(date +%s) + 12600 )) s state
    while [ -n "$(running_units)" ] && [ "$(date +%s)" -lt "$end" ]; do sleep 30; done
    [ -z "$(running_units)" ] || echo "still running after 3.5 h: $(running_units)"
    for s in $STEPS; do
        state="not started"
        [ -d "$OUT/$s.started" ] && state="started, not passed"
        [ -e "$OUT/$s.passed" ] && state="passed"
        printf '%-10s %s\n' "$s" "$state"
    done
    for s in $STEPS; do
        [ -f "$OUT/$s.result" ] && { echo "---- $s.result ----"; cat "$OUT/$s.result"; }
    done
    return 0
}

# -------------------------------------------------------------------- main --
main() {
    case " $STEPS " in *" $STEP "*) ;; *) echo "usage: s66-node.sh {${STEPS// /|}}"; exit 2 ;; esac
    [ "$(id -u)" -eq 0 ] || { echo "STOP: run as root"; exit 2; }
    [ -d "$OUT" ] && [ -d "$R" ] || { echo "STOP: $OUT or $R is missing (run the extract step first)"; exit 2; }
    # order first (a refused start does not use up the step), then once per step
    local prev="" s
    for s in $STEPS; do [ "$s" = "$STEP" ] && break; prev="$s"; done
    if [ "$STEP" = evidence ]; then
        [ -d "$OUT/preflight.started" ] || { echo "STOP: preflight has not started"; exit 3; }
        # once only, so not too early: after accept started, or after a step that failed
        local failed=""
        for s in $STEPS; do
            [ "$s" = evidence ] && break
            [ -d "$OUT/$s.started" ] && [ ! -e "$OUT/$s.passed" ] && failed="$s"
        done
        [ -d "$OUT/accept.started" ] || [ -n "$failed" ] \
            || { echo "STOP: evidence runs after accept has started or after a failed step"; exit 3; }
        [ -z "$(running_units | grep -vx 'hs6-evidence.service')" ] || { echo "STOP: another step is running"; exit 3; }
    elif [ -n "$prev" ] && [ ! -e "$OUT/$prev.passed" ]; then
        echo "STOP: step $prev has not passed"; exit 3
    fi
    if ! mkdir "$OUT/$STEP.started" 2>/dev/null; then
        echo "STOP: step $STEP has already been started on this node; a retry needs a new approval"; exit 3
    fi
    say "stage 6-6 step $STEP on $(hostname) at $(date -u +%FT%TZ)"
    "s_$STEP"
    say "step $STEP: $FAILS failed check(s)"
    [ "$FAILS" -eq 0 ] && touch "$OUT/$STEP.passed"
    [ "$FAILS" -eq 0 ]
}

case "$STEP" in
    run|status)
        [ "$(id -u)" -eq 0 ] || { echo "STOP: run as root"; exit 2; }
        [ -d "$OUT" ] || { echo "STOP: $OUT is missing (run the extract step first)"; exit 2; }
        if [ "$STEP" = run ]; then run_step "${2:-}"; else show_status; fi
        exit $? ;;
esac
case " $STEPS " in *" $STEP "*) ;; *) echo "usage: s66-node.sh {run STEP|status}, STEP one of: $STEPS"; exit 2 ;; esac
main "$@" 2>&1 | tee -a "$OUT/$STEP.log"
exit "${PIPESTATUS[0]}"
