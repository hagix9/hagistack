#!/bin/bash
# Build RPMs and SRPMs from Hagistack's own package definitions (defs/*.toml).
#
#   build-own.sh [--nocheck] [definition-name ...]     (default: every definition)
#
# environment (the same contract as the old build-rpms.sh, so build-in-container.sh
# drives either):
#   RESULTS_FILE=F   write one "PASS <name> (...)" / "FAIL <name> (rpmbuild exit N)"
#                    line per definition to F
#   WORK             work area (default ~/own-build); logs in $WORK/logs/<name>.*.log
#   RPMs and SRPMs are written under ~/rpmbuild/RPMS and ~/rpmbuild/SRPMS.
#
# Runs on a disposable Rocky Linux 10.2 builder (root, or sudo for dnf). Nothing
# here reads RDO packaging: the inputs are the definition, Hagistack's files in
# files/<name>/, the upstream tarball pinned by SHA-256 in the definition, its
# detached signature with the OpenStack release key pinned by a KEY row of
# ../gazpacho.manifest (PyPI sdists: SHA-256 only), and files under ../third-party/
# pinned by SHA-256 in the definition.
#
# Build order: definitions are tried libraries first; a definition whose build
# dependencies are not there yet (rpmbuild exit 11, "is needed by") is retried
# after the packages built so far are published as a priority=1 repository. The
# rounds stop when a round builds nothing new. Any other failure is final.
# Every name the definitions produce is excluded from every other repository
# (RDO, EPEL, Rocky, any *.repo file, enabled or not) before the first build and
# again before every dependency install, so such a dependency is only ever met by
# this build; a later round retries a definition only once this build has
# produced something new since its last attempt. The run stops (STOP) if a repository still offers one of our
# names, if a package with one of our names is installed before the first build,
# or if at the end any installed package with one of our names came from
# anywhere but this build.
# A verification failure (pin, signature, missing file) prints STOP and ends
# the whole run: nothing is built from an input that did not verify.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # also when sourced by tests
MANIFEST="$HERE/../gazpacho.manifest"
NOCHECK=0
[ "${1:-}" = "--nocheck" ] && { NOCHECK=1; shift; }
WORK="${WORK:-$HOME/own-build}"
RPMTOP="$HOME/rpmbuild"
LOGDIR="$WORK/logs"
SRCDIR="$RPMTOP/SOURCES"
mkdir -p "$RPMTOP"/{SOURCES,SPECS,RPMS,SRPMS,BUILD} "$LOGDIR"
say(){ printf '\n######## %s ########\n' "$*"; }
ok(){  printf '  ok    %s\n' "$*"; }
bad(){ printf '  FAIL  %s\n' "$*" >&2; }
die(){ printf '\nSTOP: %s\n' "$*" >&2; exit 1; }
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO=sudo
REPO_DIR="${BUILD_OWN_REPO_DIR:-/etc/yum.repos.d}"   # tests point this elsewhere
# Every directory DNF reads repository files from (its reposdir default), and
# dnf.conf, which may define repositories too.
if [ -n "${BUILD_OWN_REPO_DIR:-}" ]; then REPO_DIRS=("$REPO_DIR")
else REPO_DIRS=(/etc/yum.repos.d /etc/yum/repos.d /etc/distro.repos.d); fi
DNF_CONF="${BUILD_OWN_DNF_CONF:-/etc/dnf/dnf.conf}"
field(){ python3 -I -c 'import sys,tomllib; v=tomllib.load(open(sys.argv[1],"rb"))["source"].get(sys.argv[2],""); print(v if isinstance(v,str) else "")' "$1" "$2"; }
pinned(){ python3 -I -c 'import sys,tomllib; s=tomllib.load(open(sys.argv[1],"rb"))["source"]; [print(i["path"], i["sha256"]) for k in ("patches","extra_licenses") for i in s.get(k,[])]' "$1"; }

fetch_pinned() {   # fetch_pinned <url> <dest> <sha256>
    local got
    if [ ! -f "$2" ]; then
        curl -sSfL -o "$2.part" "$1" || die "could not fetch $1"
        mv "$2.part" "$2"
    fi
    got="$(sha256sum "$2" | cut -d' ' -f1)"
    [ "$got" = "$3" ] || { rm -f "$2"; die "$(basename "$2"): SHA-256 ${got:0:16}… is not the pinned ${3:0:16}…"; }
}

# stage <name>: fetch and verify every input, write the spec. Dies on any mismatch.
stage() {
    local name="$1" def="$HERE/defs/$1.toml" origin proj tarball tsha key ksha rel sha f
    [ -f "$def" ] || die "no definition $def"
    origin="$(field "$def" origin)"; origin="${origin:-openstack}"
    proj="$(field "$def" project)"; tarball="$(field "$def" tarball)"; tsha="$(field "$def" sha256)"
    if [ "$origin" = openstack ]; then
        key="$(field "$def" signing_key)"
        ksha="$(awk -v k="$key" '$1=="KEY" && $2==k {print $3}' "$MANIFEST")"
        [ -n "$ksha" ] || die "$name: signing key $key is not pinned by a KEY row in gazpacho.manifest"
        fetch_pinned "https://tarballs.openstack.org/$proj/$tarball" "$SRCDIR/$tarball" "$tsha"
        curl -sSfL -o "$SRCDIR/$tarball.asc" "https://tarballs.openstack.org/$proj/$tarball.asc" \
            || die "$name: no detached signature for $tarball"
        fetch_pinned "https://releases.openstack.org/_static/$key.txt" "$SRCDIR/$key.txt" "$ksha"
    else
        fetch_pinned "https://files.pythonhosted.org/packages/source/${proj:0:1}/$proj/$tarball" \
            "$SRCDIR/$tarball" "$tsha"
    fi
    while read -r rel sha; do
        [ -n "$rel" ] || continue
        f="$HERE/../$rel"
        [ -f "$f" ] && [ ! -L "$f" ] || die "$name: pinned file $rel is missing (or a symlink)"
        [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$sha" ] || die "$name: $rel does not match its pinned SHA-256"
        install -m 0644 "$f" "$SRCDIR/$(basename "$rel")"
    done < <(pinned "$def")
    install -m 0644 "$HERE/HAGISTACK-LICENSE" "$SRCDIR/HAGISTACK-LICENSE"
    if [ -d "$HERE/files/$name" ]; then
        find "$HERE/files/$name" -maxdepth 1 -type f ! -name AUTHORING.md -exec cp -p {} "$SRCDIR/" \;
    fi
    # Hagistack's logos for HTML documentation (genspec.py DOC_BRANDING), shared.
    find "$HERE/files/_docs-branding" -maxdepth 1 -type f -name 'hagistack-doc-*' -exec cp -p {} "$SRCDIR/" \;
    python3 -I "$HERE/genspec.py" "$def" -o "$RPMTOP/SPECS/$name.spec" || die "$name: spec generation failed"
}

# build <name> -> 0 built, 11 build dependencies missing, other = failed
build() {
    local name="$1" spec="$RPMTOP/SPECS/$1.spec" log="$LOGDIR/$1" nosrc round rc
    # --nobest: when the newest candidate of some dependency cannot be installed
    # (a repository moved on: an EPEL build needing a library EL does not have yet),
    # take the newest one that can. What was installed is recorded in build-env.lock.
    # A repository file added since the last check (a package dropping one into
    # yum.repos.d) gets our names excluded before anything is installed from it.
    exclude_own "$WORK/own-names.txt" > "$log.excludes.log" 2>&1 \
        || die "$name: could not exclude our names from every repository (see $log.excludes.log)"
    $SUDO dnf -y --nobest builddep "$spec" > "$log.builddep.log" 2>&1
    for round in 1 2 3; do
        rpmbuild -br --nodeps "$spec" > "$log.br.log" 2>&1
        nosrc="$(ls -t "$RPMTOP"/SRPMS/*.buildreqs.nosrc.rpm 2>/dev/null | head -1)"
        [ -n "$nosrc" ] || break
        $SUDO dnf -y --nobest builddep "$nosrc" >> "$log.builddep.log" 2>&1
        rm -f "$nosrc"
    done
    local flags=(-ba); [ "$NOCHECK" -eq 1 ] && flags+=(--nocheck)
    rpmbuild "${flags[@]}" "$spec" > "$log.rpmbuild.log" 2>&1; rc=$?
    rm -f "$RPMTOP"/SRPMS/*.buildreqs.nosrc.rpm
    return "$rc"
}

# Every binary package name the definitions produce (all of defs/, also for a
# partial run). These names are excluded from RDO's trunk repository files
# before the first build, not only once built: a build dependency on a library
# this run has not built yet must wait for it (the rounds below), never be met
# by a trunk build. A trunk build installed early stays installed ("already
# installed") and feeds every later build — on 2026-11-11 the sample
# configurations of keystone, nova, placement and neutron were generated by
# oslo.log 7.2.1 from RDO trunk instead of the oslo.log 8.1.1 built here.
own_names() {
    local d
    for d in "$HERE"/defs/*.toml; do
        python3 -I "$HERE/genspec.py" --names "$d" || return 1
    done | sort -u
}

# exclude_own <names-file>: every section of every repository file except
# hagistack-own.repo, enabled or not, excludes our names; existing exclude= lines
# are kept and extended; idempotent (own-excludes.py). Fails if a file cannot be
# rewritten, or if anything is left uncovered (also a repository in dnf.conf).
exclude_own() {
    $SUDO python3 -I "$HERE/own-excludes.py" apply "$1" "$DNF_CONF" "${REPO_DIRS[@]}"
}

# repos_offering_own <names-file>: what DNF itself, with the configuration it
# actually reads, still offers under one of our names from any repository but
# hagistack-own, as "name repository". Empty output means none; a failed query
# returns 2, never "none".
repos_offering_own() {
    local got
    # shellcheck disable=SC2046
    got="$(dnf -q repoquery --qf '%{name} %{repoid}\n' $(cat "$1") 2>/dev/null)" || return 2
    awk 'NF && $2 != "hagistack-own" && $2 != "@System" && $2 != "installed"' <<<"$got"
}

# A local repository of what is built so far, ranked above everything else.
publish_repo() {
    createrepo_c --quiet "$RPMTOP/RPMS" >/dev/null 2>&1 || { bad "createrepo_c failed"; return 1; }
    $SUDO tee "$REPO_DIR/hagistack-own.repo" >/dev/null <<EOF
# RPMs built by build-own.sh in this builder. priority=1: they win.
[hagistack-own]
name=hagistack own packaging (this build)
baseurl=file://$RPMTOP/RPMS
enabled=1
gpgcheck=0
priority=1
EOF
    $SUDO dnf -q makecache >/dev/null 2>&1 || true
}

# missing_deps <name>: the build dependencies rpmbuild reported missing, by name.
missing_deps() {
    awk '/ is needed by /{print $1}' "$LOGDIR/$1.rpmbuild.log" 2>/dev/null | sort -u
}

# ready <name>: worth another attempt — nothing was recorded, or at least one
# dependency it was missing is now provided by this build's repository, or this
# build has produced a new package since its last attempt. The last case covers
# a dependency missed indirectly: with our names excluded everywhere else, a
# build dependency from another repository (python3-cliff from EPEL) cannot be
# installed until a library of ours it requires (python3-stevedore) is built, and
# rpmbuild names only the direct one. A package is never retried without new
# packages, and the rounds end when a round builds nothing, so this is bounded.
OWN_BUILT=0
ready() {
    local d any=0 since
    [ -f "$LOGDIR/$1.missing" ] || return 0
    since="$(cat "$LOGDIR/$1.since" 2>/dev/null)"
    [[ "$since" =~ ^[0-9]+$ ]] || since=-1
    [ "$OWN_BUILT" -gt "$since" ] && return 0
    while read -r d; do
        [ -n "$d" ] || continue
        any=1
        dnf -q --disablerepo='*' --enablerepo=hagistack-own repoquery --whatprovides "$d" 2>/dev/null \
            | grep -q . && return 0
    done < "$LOGDIR/$1.missing"
    [ "$any" -eq 0 ]
}

# env_not_own: installed packages with one of our names that did not come from
# this build's repository, as "name repository". Empty output means clean; a
# failed or empty query returns 2, never "clean".
env_not_own() {
    local inst
    inst="$(dnf -q repoquery --installed --qf '%{name} %{from_repo}\n' 2>/dev/null)" || return 2
    [ -n "$inst" ] || return 2
    awk 'NR==FNR {own[$1]=1; next} ($1 in own) && $2 != "hagistack-own"' "$WORK/own-names.txt" - <<<"$inst"
}

write_lock() {
    {
        echo "# Rocky $(rpm -E %{rhel}) build environment, $(date -u +%FT%TZ)"
        echo "# Every RPM installed at build time, as name-epoch:version-release.arch."
        rpm -qa --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort
    } > "$WORK/build-env.lock"
}

# Tests source the functions only.
if [ -n "${BUILD_OWN_LIB_ONLY:-}" ]; then return 0 2>/dev/null || exit 0; fi

# The definitions to build: libraries and PyPI packages first, services last.
if [ "$#" -gt 0 ]; then WANT=("$@"); else
    mapfile -t WANT < <(cd "$HERE/defs" && ls *.toml | sed 's/\.toml$//' \
        | awk '{print (/^(openstack-|python-django-horizon$)/ ? 1 : 0) " " $0}' | sort | cut -d' ' -f2)
fi
python3 -I "$HERE/test_genspec.py" > "$LOGDIR/test_genspec.log" 2>&1 \
    || die "the definitions do not pass test_genspec.py (see $LOGDIR/test_genspec.log)"
# The dashboard images must be exactly what make-branding.py draws, and shapes only.
python3 -I "$HERE/branding/test_branding.py" > "$LOGDIR/test_branding.log" 2>&1 \
    || die "the dashboard images do not pass test_branding.py (see $LOGDIR/test_branding.log)"

say "staging ${#WANT[@]} definitions (fetch, verify, generate)"
for n in "${WANT[@]}"; do stage "$n"; done
ok "every input verified; specs generated"

own_names > "$WORK/own-names.txt" && [ -s "$WORK/own-names.txt" ] \
    || die "could not list the package names of the definitions"
exclude_own "$WORK/own-names.txt" > "$LOGDIR/excludes.log" 2>&1 \
    || die "could not exclude our names from every repository (see $LOGDIR/excludes.log)"
$SUDO dnf -q makecache >/dev/null 2>&1 || true
leak="$(repos_offering_own "$WORK/own-names.txt")" \
    || die "could not ask DNF which repositories offer our names"
[ -z "$leak" ] || die "a repository still offers packages with our names (name repository): $(echo $leak)"
ok "$(wc -l < "$WORK/own-names.txt") package names excluded from every other repository (RDO, EPEL, Rocky, ...) before the first build"
stray="$(env_not_own)" || die "could not list the installed packages to check where our names came from"
[ -z "$stray" ] || die "before the first build, the build environment already holds packages with our names from elsewhere (name repository): $(echo $stray)"
ok "no package with one of our names is installed from elsewhere before the first build"

# RPMs already in this build area (a re-run, or a partial build being completed)
# are published before the first round, so they can satisfy build dependencies.
if find "$RPMTOP/RPMS" -name '*.rpm' -print -quit | grep -q .; then publish_repo; fi

declare -A STATE
todo=("${WANT[@]}")
round=0
while [ "${#todo[@]}" -gt 0 ]; do
    round=$((round + 1))
    say "round $round: ${#todo[@]} to build"
    next=(); built=0
    for n in "${todo[@]}"; do
        if [ "$round" -gt 1 ] && ! ready "$n"; then
            next+=("$n"); printf '  wait  %s (still missing: %s)\n' "$n" "$(tr '\n' ' ' < "$LOGDIR/$n.missing")"
            continue
        fi
        build "$n"; rc=$?
        if [ "$rc" -eq 0 ]; then
            STATE[$n]="PASS $n (built in round $round; %check $([ "$NOCHECK" -eq 1 ] && echo 'NOT run' || echo 'run'))"
            ok "$n"; built=$((built + 1)); OWN_BUILT=$((OWN_BUILT + 1))
            # Published at once, not at the end of the round: a later package in the
            # same round (a service generating its sample configuration from the
            # libraries it imports) must see this build, not an RDO trunk version.
            publish_repo
        elif [ "$rc" -eq 11 ] && grep -q 'is needed by' "$LOGDIR/$n.rpmbuild.log"; then
            STATE[$n]="FAIL $n (rpmbuild exit 11)"; next+=("$n")
            missing_deps "$n" > "$LOGDIR/$n.missing"
            echo "$OWN_BUILT" > "$LOGDIR/$n.since"
            printf '  wait  %s (build dependencies not there yet)\n' "$n"
        else
            STATE[$n]="FAIL $n (rpmbuild exit $rc)"; bad "$n — see $LOGDIR/$n.rpmbuild.log"
        fi
    done
    publish_repo
    [ "$built" -gt 0 ] || break
    todo=("${next[@]}")
done

say "summary"
lines=(); for n in "${WANT[@]}"; do lines+=("${STATE[$n]:-FAIL $n (not built)}"); done
printf '  %s\n' "${lines[@]}"
[ -n "${RESULTS_FILE:-}" ] && printf '%s\n' "${lines[@]}" > "$RESULTS_FILE"
write_lock
leak="$(repos_offering_own "$WORK/own-names.txt")" \
    || die "could not ask DNF which repositories offer our names"
[ -z "$leak" ] || die "at the end, a repository offers packages with our names (name repository): $(echo $leak)"
# Fail closed: a package of ours that did not come from this build was in the
# build environment, so what was built from it is not this build's own.
stray="$(env_not_own)" || die "could not list the installed packages to check where our names came from"
[ -z "$stray" ] || die "the build environment holds packages with our names from elsewhere (name repository): $(echo $stray)"
ok "every installed package with one of our names came from this build"
printf '%s\n' "${lines[@]}" | grep -q '^FAIL' && exit 1
exit 0
