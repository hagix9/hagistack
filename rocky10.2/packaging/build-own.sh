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
# A verification failure (pin, signature, missing file) prints STOP and ends
# the whole run: nothing is built from an input that did not verify.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
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
    if [ -d "$HERE/files/$name" ]; then
        find "$HERE/files/$name" -maxdepth 1 -type f ! -name AUTHORING.md -exec cp -p {} "$SRCDIR/" \;
    fi
    python3 -I "$HERE/genspec.py" "$def" -o "$RPMTOP/SPECS/$name.spec" || die "$name: spec generation failed"
}

# build <name> -> 0 built, 11 build dependencies missing, other = failed
build() {
    local name="$1" spec="$RPMTOP/SPECS/$1.spec" log="$LOGDIR/$1" nosrc round rc
    # --nobest: when the newest candidate of some dependency cannot be installed
    # (a repository moved on: an EPEL build needing a library EL does not have yet),
    # take the newest one that can. What was installed is recorded in build-env.lock.
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

# A local repository of what is built so far, ranked above everything else, and
# the same names excluded from RDO's trunk repository files, so a dependency is
# never satisfied by a trunk build of something this run builds itself.
publish_repo() {
    local names
    createrepo_c --quiet "$RPMTOP/RPMS" >/dev/null 2>&1 || { bad "createrepo_c failed"; return 1; }
    $SUDO tee /etc/yum.repos.d/hagistack-own.repo >/dev/null <<EOF
# RPMs built by build-own.sh in this builder. priority=1: they win.
[hagistack-own]
name=hagistack own packaging (this build)
baseurl=file://$RPMTOP/RPMS
enabled=1
gpgcheck=0
priority=1
EOF
    names="$(find "$RPMTOP/RPMS" -name '*.rpm' -exec rpm -qp --qf '%{NAME}\n' {} \; 2>/dev/null | sort -u | tr '\n' ' ')"
    local f
    for f in /etc/yum.repos.d/delorean.repo /etc/yum.repos.d/delorean-deps.repo; do
        [ -f "$f" ] || continue
        $SUDO sed -i '/^exclude=.*# hagistack-own$/d' "$f"
        [ -n "${names// /}" ] && $SUDO sed -i "s|^enabled=1$|enabled=1\nexclude=$names # hagistack-own|" "$f"
    done
    $SUDO dnf -q makecache >/dev/null 2>&1 || true
}

write_lock() {
    {
        echo "# Rocky $(rpm -E %{rhel}) build environment, $(date -u +%FT%TZ)"
        echo "# Every RPM installed at build time, as name-epoch:version-release.arch."
        rpm -qa --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort
    } > "$WORK/build-env.lock"
}

# The definitions to build: libraries and PyPI packages first, services last.
if [ "$#" -gt 0 ]; then WANT=("$@"); else
    mapfile -t WANT < <(cd "$HERE/defs" && ls *.toml | sed 's/\.toml$//' \
        | awk '{print (/^(openstack-|python-django-horizon$)/ ? 1 : 0) " " $0}' | sort | cut -d' ' -f2)
fi
python3 -I "$HERE/test_genspec.py" > "$LOGDIR/test_genspec.log" 2>&1 \
    || die "the definitions do not pass test_genspec.py (see $LOGDIR/test_genspec.log)"

say "staging ${#WANT[@]} definitions (fetch, verify, generate)"
for n in "${WANT[@]}"; do stage "$n"; done
ok "every input verified; specs generated"

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
        build "$n"; rc=$?
        if [ "$rc" -eq 0 ]; then
            STATE[$n]="PASS $n (built in round $round; %check $([ "$NOCHECK" -eq 1 ] && echo 'NOT run' || echo 'run'))"
            ok "$n"; built=$((built + 1))
            # Published at once, not at the end of the round: a later package in the
            # same round (a service generating its sample configuration from the
            # libraries it imports) must see this build, not an RDO trunk version.
            publish_repo
        elif [ "$rc" -eq 11 ] && grep -q 'is needed by' "$LOGDIR/$n.rpmbuild.log"; then
            STATE[$n]="FAIL $n (rpmbuild exit 11)"; next+=("$n")
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
printf '%s\n' "${lines[@]}" | grep -q '^FAIL' && exit 1
exit 0
