#!/usr/bin/env bash
#
# Re-run the Rocky Linux 10.2 availability investigation recorded in README.md.
#
# Read-only: it fetches HTTP directory listings and repository metadata. It
# installs nothing, changes no repository configuration outside a temporary
# directory, and touches no running machine.
#
# Exit status:
#   0  every condition in README.md §4 is met — re-read the verdict
#   1  at least one condition is still unmet (the expected outcome today)
#   2  the probe itself could not run (no curl, no network)
set -uo pipefail

C_G=''; C_R=''; C_Y=''; C_0=''
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'; C_0=$'\033[0m'
fi
MET=0; UNMET=0; UNKNOWN=0
met()     { printf '  %sMET%s      %-28s %s\n' "$C_G" "$C_0" "$1" "$2"; MET=$((MET+1)); }
unmet()   { printf '  %sUNMET%s    %-28s %s\n' "$C_R" "$C_0" "$1" "$2"; UNMET=$((UNMET+1)); }
unknown() { printf '  %sUNKNOWN%s  %-28s %s\n' "$C_Y" "$C_0" "$1" "$2"; UNKNOWN=$((UNKNOWN+1)); }

command -v curl >/dev/null 2>&1 || { echo "probe-repos.sh: curl is required" >&2; exit 2; }
CURL=(curl -fsSL -m 45)
fetch() { "${CURL[@]}" "$1" 2>/dev/null; }
# Apache/nginx autoindex listings; strip the boilerplate links the CentOS and
# Rocky themes add, which are absolute URLs or start with '?'.
entries() { fetch "$1" | grep -oE 'href="[^"]*"' | sed 's/href="//;s/"//' \
            | grep -vE '^(https?:|/|\?|#)'; }

if ! fetch https://trunk.rdoproject.org/ >/dev/null; then
    echo "probe-repos.sh: cannot reach trunk.rdoproject.org — no network?" >&2
    exit 2
fi

echo "hagistack — Rocky Linux 10.2 repository probe, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Conditions are those in README.md section 4. All five must be MET before the"
echo "distributed-RPM path is worth re-evaluating."
echo

echo "== 1. does a released EL10 OpenStack repository exist? =="
cloud="$(entries https://mirror.stream.centos.org/SIGs/10-stream/cloud/x86_64/ | grep -c '^openstack-' || true)"
if [ "${cloud:-0}" -gt 0 ]; then
    met "c10s-cloud-sig" "$cloud openstack-* repositories on the 10-stream Cloud SIG"
else
    unmet "c10s-cloud-sig" "10-stream Cloud SIG still has no openstack-* repository"
fi
branches="$(fetch https://trunk.rdoproject.org/ | grep -oE 'centos10-[a-z0-9]+' | sort -u | grep -v '^centos10-master$' || true)"
if [ -n "$branches" ]; then
    met "rdo-stable-branch" "RDO now offers: $(tr '\n' ' ' <<<"$branches")"
else
    unmet "rdo-stable-branch" "RDO offers centos10-master only (self-described as untested)"
fi

echo
echo "== 2. do the six core packages build? =="
csv="$(fetch https://trunk.rdoproject.org/centos10/status_report.csv)"
if [ -z "$csv" ]; then
    unknown "rdo-build-status" "status_report.csv could not be fetched"
else
    failed=""; newest=0
    for pkg in openstack-keystone openstack-glance openstack-nova openstack-neutron \
               openstack-placement python-django-horizon; do
        row="$(grep -E "^${pkg}," <<<"$csv" | head -1)"
        st="$(cut -d, -f6 <<<"$row")"
        ts="$(cut -d, -f7 <<<"$row")"
        [ "$st" = "SUCCESS" ] || failed="$failed $pkg"
        case "$ts" in ''|*[!0-9]*) ;; *) [ "$ts" -gt "$newest" ] && newest="$ts" ;; esac
    done
    age=""
    if [ "$newest" -gt 0 ]; then
        now="$(date -u +%s)"
        age=" (newest core build $(( (now - newest) / 86400 )) days old)"
    fi
    if [ -z "$failed" ]; then
        met "rdo-build-status" "all six core packages built SUCCESS${age}"
    else
        unmet "rdo-build-status" "still FAILED:${failed}${age}"
    fi
fi

echo
echo "== 3. are the core services at one OpenStack version? =="
declare -A SEEN=()
repo="$(fetch https://trunk.rdoproject.org/centos10-master/current/delorean.repo)"
if [ -z "$repo" ]; then
    unknown "release-coherence" "current/delorean.repo could not be fetched"
else
    # Take each component repo's baseurl and read the service version out of the
    # RPM file names it publishes.
    while read -r base; do
        [ -n "$base" ] || continue
        for n in openstack-keystone openstack-glance openstack-placement-api \
                 openstack-neutron-common openstack-nova-common openstack-dashboard; do
            v="$(fetch "$base/" | grep -oE "${n}-[0-9]+\.[0-9]+\.[0-9]+" | head -1 | sed "s/^${n}-//")"
            [ -n "$v" ] && SEEN[$n]="$v"
        done
    done < <(grep -E '^baseurl=' <<<"$repo" | sed 's/^baseurl=//')
    if [ "${#SEEN[@]}" -eq 0 ]; then
        unknown "release-coherence" "no component version could be read"
    else
        line=""
        for n in "${!SEEN[@]}"; do line="$line ${n}=${SEEN[$n]}"; done
        # A coherent set would have one cycle; we can only report the spread.
        printf '     versions:%s\n' "$line"
        unmet "release-coherence" "compare against one upstream cycle by hand — README §1.3 recorded 2025.1 + 2025.2 + 2026.1"
    fi
fi

echo
echo "== 4. are OVS and OVN still on the RELEASED 10-stream NFV mirror? =="
mirror_rpms="$(entries https://mirror.stream.centos.org/SIGs/10-stream/nfv/x86_64/openvswitch-2/Packages/o/ | grep -cE '^(ovn|openvswitch)[0-9]' || true)"
build_rpms="$(entries https://buildlogs.centos.org/centos/10-stream/nfv/x86_64/openvswitch-2/Packages/o/ | grep -cE '^(ovn|openvswitch)[0-9]' || true)"
if [ "${mirror_rpms:-0}" -gt 0 ]; then
    met "ovs-ovn-released" "$mirror_rpms OVS/OVN RPMs on the released mirror (buildlogs: ${build_rpms:-0})"
else
    unmet "ovs-ovn-released" "released mirror now has none; only buildlogs (${build_rpms:-0} RPMs, an artifact area that is pruned)"
fi

echo
echo "== 5. is there a STABLE repository URL, or a content hash? =="
if grep -qE 'baseurl=.*/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{40}' <<<"${repo:-}"; then
    unmet "stable-repo-url" "component baseurls are still content-hash pinned; they move on every build"
elif [ -n "${repo:-}" ]; then
    met "stable-repo-url" "component baseurls no longer look hash-pinned"
else
    unknown "stable-repo-url" "delorean.repo could not be fetched"
fi

echo
echo "== supporting facts (not conditions) =="
for u in "https://dl.rockylinux.org/pub/rocky/10/AppStream/x86_64/os/Packages/o/|Rocky 10 AppStream openvswitch/ovn" \
         "https://dl.fedoraproject.org/pub/epel/10/Everything/x86_64/Packages/r/|EPEL 10 rabbitmq"; do
    url="${u%%|*}"; label="${u#*|}"
    n="$(entries "$url" | grep -cE '^(ovn|openvswitch|rabbitmq)' || true)"
    printf '  %-46s %s\n' "$label" "${n:-0} matching RPM(s)"
done
n="$(entries https://trunk.rdoproject.org/centos10/rabbitmq/ | grep -cE '^rabbitmq-server.*\.rpm$' || true)"
printf '  %-46s %s\n' "RDO centos10 rabbitmq-server" "${n:-0} RPM(s)"

if command -v dnf >/dev/null 2>&1 && [ -r /etc/os-release ] \
   && grep -qE '^ID(_LIKE)?=.*(rhel|rocky|centos|fedora)' /etc/os-release; then
    echo
    echo "== on-host dnf resolution (this machine) =="
    echo "  not run automatically: it needs the RDO repo files installed under"
    echo "  /etc/yum.repos.d. README.md section 1.3 records the exact command."
fi

echo
printf 'conditions: %sMET %d%s  %sUNMET %d%s  %sUNKNOWN %d%s\n' \
    "$C_G" "$MET" "$C_0" "$C_R" "$UNMET" "$C_0" "$C_Y" "$UNKNOWN" "$C_0"
if [ "$UNMET" -eq 0 ] && [ "$UNKNOWN" -eq 0 ]; then
    echo "Every condition is met. Re-read README.md section 4 and re-evaluate."
    exit 0
fi
echo "Not every condition is met: Rocky Linux 10.2 stays NOT IMPLEMENTED."
echo "This says nothing about source builds, self-built RPMs or Rocky 9 —"
echo "see README.md section 3 for what was deliberately not investigated."
exit 1
