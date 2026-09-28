#!/usr/bin/env bash
# Build OpenStack 2025.1 Epoxy RPMs on Rocky Linux 10.2 from pinned inputs.
#
# This replaces build-keystone-epoxy.sh, which fetched raw files from the
# `epoxy-rdo` BRANCH. A branch name proves nothing about what you got: RDO can
# push to it at any time and the next run silently builds different software.
# Here every input is pinned in ./epoxy.manifest and verified before use:
#
#   * the distgit is checked out at an exact COMMIT ID and `git rev-parse HEAD`
#     is compared with the manifest. A commit id is content-addressed, so this
#     fixes the entire spec tree — spec, patches, logrotate files and all.
#   * the upstream tarball is compared against a pinned sha256, AND the spec's
#     own %prep runs %{gpgverify} against the OpenStack release signing key.
#   * a fetch failure or a digest mismatch STOPS the build. Nothing falls back
#     to "latest", and no unverified file is ever handed to rpmbuild.
#
# usage:  ./build-epoxy.sh [package ...]     (default: every row in the manifest)
#         ./build-epoxy.sh --lock            (write a build-environment lock)
#         ./build-epoxy.sh --publish         (re-publish the local repo only)
#
# Run it in a throwaway VM or container: it installs build dependencies as root.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/epoxy.manifest"
WORK="${WORK:-$HOME/epoxy-build}"
RPMTOP="$HOME/rpmbuild"
LOGDIR="$WORK/logs"
DISTGIT_BASE="${DISTGIT_BASE:-https://github.com/rdo-packages}"
KEY_URL=https://releases.openstack.org/_static/0x22284f69d9eccdf3df7819791c711af193ff8e54.txt
KEY_SHA256=56ae1e9ba54e609920e3c7e92740e2f3b0f93fe7e4cc4fa1b0e6440682229997

say(){ printf '\n######## %s ########\n' "$*"; }
ok(){  printf '  ok    %s\n' "$*"; }
bad(){ printf '  FAIL  %s\n' "$*" >&2; }
die(){ printf '\nSTOP: %s\n' "$*" >&2; exit 1; }

[ -r "$MANIFEST" ] || die "manifest not found: $MANIFEST"
command -v git >/dev/null      || die "git is required"
command -v rpmbuild >/dev/null || die "rpmbuild is required (dnf install rpm-build rpmdevtools)"

mkdir -p "$WORK" "$LOGDIR"
rpmdev-setuptree
SRC="$RPMTOP/SOURCES"
SPECS="$RPMTOP/SPECS"

# ---------------------------------------------------------------------------
# verified fetch: a digest mismatch is fatal, and the bad file is removed so a
# later step cannot pick it up.
# ---------------------------------------------------------------------------
fetch_pinned() {   # fetch_pinned <url> <dest> <sha256>
    local url="$1" dest="$2" want="$3" got
    if [ -f "$dest" ]; then
        got="$(sha256sum "$dest" | cut -d' ' -f1)"
        [ "$got" = "$want" ] && { ok "cached, digest matches: $(basename "$dest")"; return 0; }
        printf '  re-fetching %s (cached copy has the wrong digest)\n' "$(basename "$dest")"
        rm -f "$dest"
    fi
    curl -sSfL -o "$dest" "$url" || { rm -f "$dest"; die "fetch failed: $url"; }
    got="$(sha256sum "$dest" | cut -d' ' -f1)"
    if [ "$got" != "$want" ]; then
        rm -f "$dest"
        die "digest mismatch for $url
       expected $want
       got      $got
     The file has been deleted. Nothing unverified is handed to rpmbuild."
    fi
    ok "fetched and verified: $(basename "$dest")  ${got:0:16}…"
}

# ---------------------------------------------------------------------------
# distgit at an exact commit
# ---------------------------------------------------------------------------
checkout_pinned() {   # checkout_pinned <repo> <commit> -> prints the checkout dir
    local repo="$1" want="$2" dir="$WORK/distgit/$repo" got
    mkdir -p "$(dirname "$dir")"
    if [ ! -d "$dir/.git" ]; then
        git clone -q "$DISTGIT_BASE/$repo" "$dir" >/dev/null 2>&1 \
            || die "cannot clone $DISTGIT_BASE/$repo"
    fi
    git -C "$dir" fetch -q origin >/dev/null 2>&1 || true
    git -C "$dir" checkout -q --detach "$want" >/dev/null 2>&1 \
        || die "commit $want is not in $repo — the pin does not exist upstream"
    got="$(git -C "$dir" rev-parse HEAD)"
    [ "$got" = "$want" ] || die "checkout of $repo is $got, manifest pins $want"
    # A dirty tree would mean the build input is not what the commit says.
    [ -z "$(git -C "$dir" status --porcelain)" ] \
        || die "$repo checkout is dirty; refusing to build from an unpinned tree"
    printf '%s\n' "$dir"
}

# ---------------------------------------------------------------------------
# one package
# ---------------------------------------------------------------------------
build_one() {   # build_one <pkg> <repo> <commit> <specfile> <tarball> <sha256> <urlproj>
    local pkg="$1" repo="$2" commit="$3" specfile="$4" tarball="$5" tsha="$6" urlproj="$7"
    say "$pkg — distgit $repo @ ${commit:0:12}"

    local dir; dir="$(checkout_pinned "$repo" "$commit")" || exit 1
    ok "distgit at $commit (verified)"

    [ -f "$dir/$specfile" ] || die "$specfile is not in $repo at $commit"
    install -m 0644 "$dir/$specfile" "$SPECS/$specfile"
    # every other tracked file in the distgit is a Source/Patch
    local f
    while IFS= read -r f; do
        [ "$f" = "$specfile" ] && continue
        case "$f" in *.spec) continue ;; esac
        install -D -m 0644 "$dir/$f" "$SRC/$(basename "$f")"
    done < <(git -C "$dir" ls-files)
    ok "spec + $(git -C "$dir" ls-files | grep -vc '\.spec$') distgit source files staged"

    # tarballs.openstack.org groups by project name, which is the manifest's
    # last column: usually the package name, but oslo.limit publishes under a
    # dotted name while its tarball uses an underscore.
    fetch_pinned "https://tarballs.openstack.org/$urlproj/$tarball" "$SRC/$tarball" "$tsha"
    curl -sSfL -o "$SRC/$tarball.asc" "https://tarballs.openstack.org/$urlproj/$tarball.asc" \
        || die "the detached signature for $tarball could not be fetched"
    ok "detached signature fetched (verified by %gpgverify in %prep)"
    fetch_pinned "$KEY_URL" "$SRC/$(basename "$KEY_URL")" "$KEY_SHA256"

    local spec="$SPECS/$specfile"
    say "$pkg — build dependencies"
    sudo dnf -y builddep "$spec" > "$LOGDIR/$pkg.builddep.log" 2>&1
    printf '  static builddep exit=%s\n' "$?"
    # pyproject-rpm-macros emits more BuildRequires during %generate_buildrequires.
    local round
    for round in 1 2 3; do
        rpmbuild -br --nodeps "$spec" > "$LOGDIR/$pkg.br.log" 2>&1
        local nosrc; nosrc="$(ls -t "$RPMTOP"/SRPMS/*.buildreqs.nosrc.rpm 2>/dev/null | head -1)"
        [ -n "$nosrc" ] || break
        sudo dnf -y builddep "$nosrc" >> "$LOGDIR/$pkg.builddep.log" 2>&1
        rm -f "$nosrc"
    done
    # setup.py compile_catalog needs Babel registered as a setuptools command;
    # neither builddep pass pulls it in.
    sudo dnf -y install python3-babel >/dev/null 2>&1

    say "$pkg — rpmbuild"
    rpmbuild -bb "$spec" > "$LOGDIR/$pkg.rpmbuild.log" 2>&1
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "rpmbuild exit=0"
        grep -aE "Good signature|gpgverify" "$LOGDIR/$pkg.rpmbuild.log" | head -3 | sed 's/^/      /'
        find "$RPMTOP/RPMS" -name "*.rpm" -newer "$spec" -printf '      %f\n' | sort
        RESULTS+=("PASS $pkg")
    else
        bad "rpmbuild exit=$rc — see $LOGDIR/$pkg.rpmbuild.log"
        grep -aE "^error:|No matching package|is needed by|RPM build error|Bad exit status" \
            "$LOGDIR/$pkg.rpmbuild.log" | sort -u | head -12 | sed 's/^/      /' >&2
        RESULTS+=("FAIL $pkg (rpmbuild exit $rc)")
    fi
    df -m / | awk 'NR==2{printf "  disk: %s MB free\n", $4}'
}

# ---------------------------------------------------------------------------
# publish: turn the built RPMs into a repository that OUTRANKS RDO trunk
#
# This is not cosmetic. RDO's centos10-master repositories carry trunk versions
# of the OpenStack libraries, and they are almost always NEWER than the release
# ones. So a self-built 2025.1 library does not stay installed: the next
# `dnf builddep` upgrades it straight back to trunk and the release you thought
# you pinned is gone. Measured on 2026-09-28: python3-oslo-limit was downgraded
# to the Epoxy 2.6.1, and the following glance builddep pulled 2.8.0 back in,
# so glance failed its test suite again with exactly the same TypeError.
#
# Two things are therefore needed, not one:
#   * a local repository of the self-built RPMs at priority=1, and
#   * an explicit `exclude=` in the RDO repositories for every package we build,
#     so trunk cannot re-supply it at any version.
# ---------------------------------------------------------------------------
publish_repo() {
    local repodir="$RPMTOP/RPMS" names=() n
    command -v createrepo_c >/dev/null || { bad "createrepo_c is not installed; cannot publish"; return 1; }
    createrepo_c --quiet "$repodir" >/dev/null || { bad "createrepo_c failed"; return 1; }

    sudo tee /etc/yum.repos.d/hagistack-epoxy.repo >/dev/null <<EOF
# Self-built OpenStack 2025.1 Epoxy for Rocky Linux 10, produced by
# build-epoxy.sh from the pinned inputs in epoxy.manifest.
# priority=1 so these win over RDO's centos10-master trunk builds.
[hagistack-epoxy]
name=hagistack self-built OpenStack 2025.1 Epoxy (Rocky 10)
baseurl=file://$repodir
enabled=1
gpgcheck=0
priority=1
EOF

    # every binary package name we produced, so trunk cannot re-supply any of them
    while IFS= read -r n; do names+=("$n"); done < <(
        find "$repodir" -name '*.rpm' -exec rpm -qp --qf '%{NAME}\n' {} \; 2>/dev/null | sort -u)
    [ ${#names[@]} -gt 0 ] || { bad "no RPMs found under $repodir"; return 1; }
    local excl="${names[*]}"
    local f
    for f in /etc/yum.repos.d/delorean.repo /etc/yum.repos.d/delorean-deps.repo; do
        [ -f "$f" ] || continue
        sudo sed -i '/^exclude=.*# hagistack-epoxy$/d' "$f"
        sudo sed -i "s|^enabled=1$|enabled=1\nexclude=$excl # hagistack-epoxy|" "$f"
    done
    sudo dnf -q makecache >/dev/null 2>&1 || true
    ok "published $repodir as [hagistack-epoxy] (priority=1)"
    ok "excluded ${#names[@]} package names from the RDO trunk repositories"
    printf '      %s\n' "$excl" | fold -s -w 100 | sed 's/^/      /'
}

# ---------------------------------------------------------------------------
# build-environment lock: what the RPMs were actually built against
# ---------------------------------------------------------------------------
write_lock() {
    local lock="$WORK/build-env.lock"
    {
        echo "# Rocky $(rpm -E %{rhel}) build environment, $(date -u +%FT%TZ)"
        echo "# Every RPM installed at build time, as name-epoch:version-release.arch."
        echo "# Re-creating a builder from this file reproduces the inputs exactly."
        rpm -qa --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort
    } > "$lock"
    ok "build environment locked: $lock ($(wc -l < "$lock") packages)"
}

# ---------------------------------------------------------------------------
RESULTS=()
WANT=("$@")
if [ "${1:-}" = "--lock" ]; then write_lock; exit 0; fi
if [ "${1:-}" = "--publish" ]; then publish_repo; exit $?; fi

while read -r pkg repo commit specfile tarball tsha urlproj _rest; do
    case "$pkg" in ''|\#*) continue ;; esac
    if [ ${#WANT[@]} -gt 0 ]; then
        printf '%s\n' "${WANT[@]}" | grep -qx "$pkg" || continue
    fi
    build_one "$pkg" "$repo" "$commit" "$specfile" "$tarball" "$tsha" "${urlproj:-$pkg}"
done < "$MANIFEST"

say "summary"
printf '  %s\n' "${RESULTS[@]:-（no package matched）}"
say "publishing the built RPMs so the release stays pinned"
publish_repo || true
write_lock
# A non-zero exit whenever anything failed: this script never reports a partial
# build set as success.
printf '%s\n' "${RESULTS[@]:-}" | grep -q '^FAIL' && exit 1
exit 0
