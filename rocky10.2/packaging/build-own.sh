#!/bin/bash
# Build RPMs and SRPMs from Hagistack's own package definitions (defs/*.toml).
#
#   build-own.sh <outdir> <definition-name>...      e.g. build-own.sh /out python-stevedore
#
# Runs on a Rocky Linux 10.2 builder that has rpm-build, pyproject-rpm-macros,
# python3 (3.12, for tomllib), gnupg2 and sudo dnf, and repositories that carry
# the build dependencies. Nothing here reads RDO packaging: the only inputs are
# the definition, Hagistack's files under files/<srpm-name>/, the upstream
# tarball pinned by SHA-256 in the definition, its detached signature, and the
# OpenStack release key pinned by SHA-256 in ../gazpacho.manifest (KEY rows).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/../gazpacho.manifest"
OUT="${1:?usage: build-own.sh <outdir> <definition>...}"; shift
[ "$#" -gt 0 ] || { echo "usage: build-own.sh <outdir> <definition>..." >&2; exit 2; }
TOP="${RPMTOP:-$HOME/rpmbuild-own}"
mkdir -p "$TOP"/{SOURCES,SPECS,RPMS,SRPMS,BUILD} "$OUT"/{repo,srpms,logs}
die(){ printf 'STOP: %s\n' "$*" >&2; exit 1; }
field(){ python3 -I -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["source"][sys.argv[2]])' "$1" "$2"; }

fetch_pinned() {   # fetch_pinned <url> <dest> <sha256>
    local got
    if [ ! -f "$2" ]; then curl -sSfL -o "$2.part" "$1" || die "could not fetch $1"; mv "$2.part" "$2"; fi
    got="$(sha256sum "$2" | cut -d' ' -f1)"
    [ "$got" = "$3" ] || { rm -f "$2"; die "$(basename "$2"): SHA-256 ${got:0:16}… is not the pinned ${3:0:16}…"; }
}

rc=0
for name in "$@"; do
    def="$HERE/defs/$name.toml"
    [ -f "$def" ] || die "no definition $def"
    proj="$(field "$def" project)"; tarball="$(field "$def" tarball)"
    tsha="$(field "$def" sha256)"; key="$(field "$def" signing_key)"
    ksha="$(awk -v k="$key" '$1=="KEY" && $2==k {print $3}' "$MANIFEST")"
    [ -n "$ksha" ] || die "$name: signing key $key is not pinned by a KEY row in gazpacho.manifest"
    fetch_pinned "https://tarballs.openstack.org/$proj/$tarball" "$TOP/SOURCES/$tarball" "$tsha"
    curl -sSfL -o "$TOP/SOURCES/$tarball.asc" "https://tarballs.openstack.org/$proj/$tarball.asc" \
        || die "$name: no detached signature for $tarball"
    fetch_pinned "https://releases.openstack.org/_static/$key.txt" "$TOP/SOURCES/$key.txt" "$ksha"
    if [ -d "$HERE/files/$name" ]; then
        find "$HERE/files/$name" -maxdepth 1 -type f ! -name AUTHORING.md -exec cp -p {} "$TOP/SOURCES/" \;
    fi
    spec="$TOP/SPECS/$name.spec"
    python3 -I "$HERE/genspec.py" "$def" -o "$spec" || die "$name: spec generation failed"
    log="$OUT/logs/$name"
    sudo dnf -y builddep "$spec" > "$log.builddep.log" 2>&1
    for round in 1 2 3; do
        rpmbuild --define "_topdir $TOP" -br --nodeps "$spec" > "$log.br.log" 2>&1
        nosrc="$(ls -t "$TOP"/SRPMS/*.buildreqs.nosrc.rpm 2>/dev/null | head -1)"
        [ -n "$nosrc" ] || break
        sudo dnf -y builddep "$nosrc" >> "$log.builddep.log" 2>&1
        rm -f "$nosrc"
    done
    if rpmbuild --define "_topdir $TOP" -ba "$spec" > "$log.rpmbuild.log" 2>&1; then
        echo "PASS $name"
    else
        echo "FAIL $name (see $log.rpmbuild.log)"; rc=1
    fi
done
find "$TOP/RPMS" -name '*.rpm' -exec cp -p {} "$OUT/repo/" \;
find "$TOP/SRPMS" -name '*.src.rpm' ! -name '*.nosrc.rpm' -exec cp -p {} "$OUT/srpms/" \;
exit "$rc"
