#!/usr/bin/env bash
# build-in-container.sh — the builder side of `hagistack --rpm-source build`.
#
# It is not meant to be run by hand on a host. hagistack starts it inside a
# disposable Rocky Linux 10 container, so that everything a build needs and an
# OpenStack node must never have — `dnf builddep` as root, RDO's trunk
# repositories (delorean.repo carries the delorean-component-* trees) — lives
# and dies with that container. The host only ever sees the finished
# repository in /out.
#
# Mounts, all set up by hagistack:
#   /src    rocky10.2/ of this checkout, read-only (build-rpms.sh, manifest, ...)
#   /build  persistent work area: HOME for the build, so distgit clones,
#           tarballs and rpmbuild state survive a re-run of the same inputs
#   /out    the result: repo/ (RPMs + repodata), srpms/, logs/, build-env.lock
#
# Exit status: 0 only when every manifest package built, in at most two passes.
set -uo pipefail

say(){ printf '\n==== %s ====\n' "$*"; }
die(){ printf '\nSTOP: %s\n' "$*" >&2; exit 1; }

[ -r /src/build-rpms.sh ] || die "/src/build-rpms.sh is missing (mount rocky10.2/ at /src)"
[ -d /build ] && [ -d /out ] || die "/build and /out must be mounted"
[ "$(id -u)" -eq 0 ] || die "run as root inside the container"

export HOME=/build
export WORK=/build/work
mkdir -p "$WORK" /out/logs /out/repo /out/srpms

# The build host's name is recorded in every RPM header (BUILDHOST). With host
# networking that would be the node's cloud-internal FQDN, which can carry a
# project or account id, so the RPMs would publish it. A neutral name instead.
printf '%s\n' '%_topdir %(echo $HOME)/rpmbuild' '%_buildhost hagistack-builder' > /build/.rpmmacros

say "builder repositories"
# Exactly the builder inputs the recorded builds used: Rocky BaseOS/AppStream/
# CRB, EPEL 10, and RDO's EL10 repository files for build dependencies. The RDO
# files are mutable (current/, deps/latest), so their content on the day is
# recorded by digest rather than pretended to be pinned by URL.
dnf -y -q install dnf-plugins-core >/dev/null || die "dnf-plugins-core did not install"
dnf config-manager --set-enabled crb >/dev/null 2>&1 || die "could not enable CRB"
dnf -y -q install epel-release >/dev/null || die "epel-release did not install"
curl -sSfL -o /etc/yum.repos.d/delorean.repo \
    https://trunk.rdoproject.org/centos10-master/current/delorean.repo \
    || die "could not fetch RDO delorean.repo"
curl -sSfL -o /etc/yum.repos.d/delorean-deps.repo \
    https://trunk.rdoproject.org/centos10-master/delorean-deps.repo \
    || die "could not fetch RDO delorean-deps.repo"
sha256sum /etc/yum.repos.d/delorean.repo /etc/yum.repos.d/delorean-deps.repo \
    | tee /out/logs/builder-repo-files.sha256

say "builder tools"
dnf -y -q install git curl rpm-build rpmdevtools createrepo_c python3 sudo \
    gnupg2 tar gzip findutils >/dev/null || die "builder tools did not install"
# build-rpms.sh calls sudo for dnf; root needs no password but sudo must exist.

# A results file per pass, so the second pass rebuilds only what failed.
run_pass() {   # run_pass <n> [package ...]
    local n="$1"; shift
    say "build pass $n${*:+: $*}"
    ( cd /src && RESULTS_FILE="/out/logs/pass$n.results" BUILD_SRPMS=1 \
        ./build-rpms.sh --nocheck "$@" ) > "/out/logs/pass$n.log" 2>&1
    local rc=$?
    tail -n 80 "/out/logs/pass$n.log" | grep -E '^  (PASS|FAIL)|STOP' || true
    return "$rc"
}

# Pass 1 builds everything. The manifest lists the services before the 2026.1
# libraries they need, so on a clean builder neutron, nova and horizon fail on
# missing build dependencies; build-rpms.sh publishes what did build at
# priority=1 at the end of the pass, which is exactly what the second pass
# needs. This is the recorded two-pass procedure, automated — not a retry loop.
run_pass 1
failed="$(awk '$1=="FAIL"{print $2}' /out/logs/pass1.results 2>/dev/null | sort -u | tr '\n' ' ')"
if grep -q '^STOP' /out/logs/pass1.log; then
    grep '^STOP' -A4 /out/logs/pass1.log >&2
    die "pass 1 stopped on a verification failure; nothing is retried after a STOP"
fi
if [ -n "$failed" ]; then
    run_pass 2 $failed
    if grep -q '^STOP' /out/logs/pass2.log; then
        grep '^STOP' -A4 /out/logs/pass2.log >&2
        die "pass 2 stopped on a verification failure"
    fi
    still="$(awk '$1=="FAIL"{print $2}' /out/logs/pass2.results 2>/dev/null | sort -u | tr '\n' ' ')"
    [ -z "$still" ] || die "these packages failed in both passes: $still (logs: /out/logs, $WORK/logs)"
fi

say "collecting the result"
# Copy, never move: /build keeps its rpmbuild tree so a later run can reuse it.
rm -rf /out/repo /out/srpms; mkdir -p /out/repo /out/srpms
find /build/rpmbuild/RPMS -name '*.rpm' -exec cp -p {} /out/repo/ \;
find /build/rpmbuild/SRPMS -name '*.src.rpm' -exec cp -p {} /out/srpms/ \;
# gzip metadata on purpose: hagistack verifies repodata with the Python
# standard library on the node, which reads gzip but has no zstd.
createrepo_c --quiet --general-compress-type=gz /out/repo \
    || die "createrepo_c failed on /out/repo"
cp -p "$WORK/build-env.lock" /out/build-env.lock 2>/dev/null || true
cp -rp "$WORK/logs" /out/logs/packages 2>/dev/null || true
printf '%s RPMs, %s SRPMs\n' "$(find /out/repo -name '*.rpm' | wc -l)" \
    "$(find /out/srpms -name '*.src.rpm' | wc -l)"
exit 0
