#!/usr/bin/env bash
# Build OpenStack RPMs on Rocky Linux 10.2 from pinned inputs.
#
#   ./build-rpms.sh --manifest gazpacho.manifest [package ...]   <- 2026.1, the target
#   ./build-rpms.sh --manifest epoxy.manifest    [package ...]   <- 2025.1, kept as a record
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
# Two things differ between the two manifests, and both are handled here rather
# than by hand:
#
#   * RDO's `rpm-master` specs — the only ones that exist for anything newer
#     than 2025.1 — ship `Version: XXX` and `Release: XXX`, because DLRN fills
#     them in at build time. The manifest therefore carries the version and
#     release, and this script substitutes them, saying so in the log. The
#     `epoxy-rdo` specs carry real values and are left alone.
#   * A spec written against master does not always match a released tarball.
#     Where it does not, the difference is a reviewable patch in ./spec-patches
#     rather than an inline sed, and a patch that does not apply STOPS the
#     build.
#
# --nocheck skips %check. That is a deliberate, recorded choice, not a default:
# the test suites here run to 121 166 tests (os-ken) and 21 189 (neutron), and
# re-running them on a second architecture proves little about noarch Python
# while costing hours. When it is used, the log says so for every package and
# the result is written down as "%check not run" rather than as a pass.
#
# usage:  ./build-rpms.sh [--manifest FILE] [--nocheck] [package ...]
#         ./build-rpms.sh [--manifest FILE] --lock      (build-environment lock)
#         ./build-rpms.sh [--manifest FILE] --publish   (re-publish the repo only)
#
# Run it in a throwaway VM or container: it installs build dependencies as root.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/gazpacho.manifest"
PATCHDIR="$HERE/spec-patches"
NOCHECK=0
# these have to be parsed before anything reads $MANIFEST
while :; do
    case "${1:-}" in
        --manifest)
            [ -n "${2:-}" ] || { echo "--manifest needs a file" >&2; exit 2; }
            case "$2" in /*) MANIFEST="$2" ;; *) MANIFEST="$HERE/$2" ;; esac
            shift 2 ;;
        --nocheck) NOCHECK=1; shift ;;
        *) break ;;
    esac
done
WORK="${WORK:-$HOME/epoxy-build}"
RPMTOP="$HOME/rpmbuild"
LOGDIR="$WORK/logs"
DISTGIT_BASE="${DISTGIT_BASE:-https://github.com/rdo-packages}"
# The OpenStack release signing key is NOT a constant: 2025.1 specs verify
# against 0x22284f69…, the rpm-master specs against 0x2426b928…. The spec names
# the one it wants in `%global sources_gpg_sign`, so it is read from there and
# looked up in the manifest's KEY table. An unknown key id stops the build —
# fetching whatever key a spec asks for would make %gpgverify meaningless.
KEY_BASE=https://releases.openstack.org/_static

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
# a PyPI package, from the generic template
#
# Ten of Horizon's dependencies are pure-Python PyPI packages that EL10 either
# carries too old or does not carry at all, and none has an RDO distgit. They
# are built from one template so the versions live in the manifest rather than
# in ten hand-written spec files.
#
# These are pinned by sha256 and NOT by signature: PyPI sdists are unsigned, so
# the GPG chain that protects the OpenStack tarballs does not exist here. That
# is a real difference and it is not papered over.
# ---------------------------------------------------------------------------
TEMPLATE="$HERE/spec-templates/python-pypi-generic.spec.in"

build_pypi() {   # build_pypi <rpm-name> <pypi-name> <version> <sdist> <sha256> <license> <summary>
    local rpmname="$1" pypi="$2" version="$3" sdist="$4" tsha="$5" lic="$6"; shift 6
    local summary="$*"
    say "$rpmname — PyPI $pypi $version (sha256-pinned, unsigned upstream)"
    [ -r "$TEMPLATE" ] || die "spec template not found: $TEMPLATE"

    # PyPI's files are addressed by a content hash, so fetch through the stable
    # /packages/source/ path and let fetch_pinned check the digest.
    local first="${pypi:0:1}"
    local url="https://files.pythonhosted.org/packages/source/${first}/${pypi}/${sdist}"
    fetch_pinned "$url" "$SRC/$sdist" "$tsha"

    local topdir
    topdir="$(tar tzf "$SRC/$sdist" 2>/dev/null | head -1 | cut -d/ -f1)"
    [ -n "$topdir" ] || die "$sdist does not look like a tarball"

    local spec="$SPECS/$rpmname.spec"
    sed -e "s|@RPM_NAME@|$rpmname|g" \
        -e "s|@PYPI_NAME@|$pypi|g" \
        -e "s|@VERSION@|$version|g" \
        -e "s|@RELEASE@|1|g" \
        -e "s|@SDIST@|$sdist|g" \
        -e "s|@TOPDIR@|$topdir|g" \
        -e "s|@LICENSE@|$lic|g" \
        -e "s|@SUMMARY@|$summary|g" \
        -e "s|@DATE@|$(LC_ALL=C date '+%a %b %d %Y')|g" \
        "$TEMPLATE" > "$spec"
    ok "spec generated from the template (unpacks into $topdir)"

    say "$rpmname — build dependencies"
    sudo dnf -y builddep "$spec" > "$LOGDIR/$rpmname.builddep.log" 2>&1
    printf '  static builddep exit=%s\n' "$?"
    local round
    for round in 1 2 3; do
        rpmbuild -br --nodeps "$spec" > "$LOGDIR/$rpmname.br.log" 2>&1
        local nosrc; nosrc="$(ls -t "$RPMTOP"/SRPMS/*.buildreqs.nosrc.rpm 2>/dev/null | head -1)"
        [ -n "$nosrc" ] || break
        sudo dnf -y builddep "$nosrc" >> "$LOGDIR/$rpmname.builddep.log" 2>&1
        rm -f "$nosrc"
    done

    say "$rpmname — rpmbuild"
    local checkflag=""
    [ "$NOCHECK" -eq 1 ] && checkflag="--nocheck"
    # shellcheck disable=SC2086
    rpmbuild -bb $checkflag "$spec" > "$LOGDIR/$rpmname.rpmbuild.log" 2>&1
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "rpmbuild exit=0"
        find "$RPMTOP/RPMS" -name "$rpmname-$version*.rpm" -printf '      %f\n' | sort
        RESULTS+=("PASS $rpmname (PyPI; built; %check $([ "$NOCHECK" -eq 1 ] && echo 'NOT run' || echo 'per spec'))")
    else
        bad "rpmbuild exit=$rc — see $LOGDIR/$rpmname.rpmbuild.log"
        grep -aE "^error:|No matching package|is needed by|File not found" \
            "$LOGDIR/$rpmname.rpmbuild.log" | sort -u | head -8 | sed 's/^/      /' >&2
        RESULTS+=("FAIL $rpmname (PyPI, rpmbuild exit $rc)")
    fi
}

# ---------------------------------------------------------------------------
# one package
# ---------------------------------------------------------------------------
build_one() {   # build_one <pkg> <repo> <commit> <spec> <version> <release> <tarball> <sha256> <urlproj> <signing-key>
    local pkg="$1" repo="$2" commit="$3" specfile="$4" version="$5" release="$6"
    local tarball="$7" tsha="$8" urlproj="$9" wantkey="${10:-}"
    say "$pkg — distgit $repo @ ${commit:0:12}"

    local gitdir; gitdir="$(checkout_pinned "$repo" "$commit")" || exit 1
    ok "distgit at $commit (verified)"

    # Work on a copy, so the pinned git checkout stays pristine and the
    # dirty-tree check above keeps meaning something on the next run.
    local dir="$WORK/staged/$pkg"
    rm -rf "$dir"; mkdir -p "$(dirname "$dir")"
    cp -a "$gitdir" "$dir"; rm -rf "$dir/.git"

    # A spec written against master is not always right for a released tarball,
    # and neither is a vhost the distgit ships beside it. Keep every such
    # difference visible and reviewable: one patch per package over the whole
    # distgit tree, applied with --dry-run first, and a hard stop if it does not
    # apply — a silently skipped patch means building something other than what
    # was reviewed.
    if [ -f "$PATCHDIR/$pkg.patch" ]; then
        patch -p1 --dry-run -d "$dir" < "$PATCHDIR/$pkg.patch" >/dev/null 2>&1 \
            || die "spec-patches/$pkg.patch does not apply to $repo at $commit"
        patch -p1 -s -d "$dir" < "$PATCHDIR/$pkg.patch" \
            || die "spec-patches/$pkg.patch failed to apply"
        ok "applied spec-patches/$pkg.patch ($(grep -c '^@@' "$PATCHDIR/$pkg.patch") hunk(s))"
    fi

    [ -f "$dir/$specfile" ] || die "$specfile is not in $repo at $commit"
    install -m 0644 "$dir/$specfile" "$SPECS/$specfile"

    # RDO's rpm-master specs carry `Version: XXX` / `Release: XXX` for DLRN to
    # fill in. Substitute from the manifest, and say so — an unsubstituted XXX
    # would otherwise fail much later with a confusing message.
    if grep -qE "^Version:[[:space:]]+XXX" "$SPECS/$specfile"; then
        [ -n "$version" ] && [ "$version" != "-" ] \
            || die "$specfile has 'Version: XXX' and the manifest gives no version"
        sed -i -E "s/^Version:([[:space:]]+)XXX/Version:\\1$version/" "$SPECS/$specfile"
        sed -i -E "s/^Release:([[:space:]]+)XXX/Release:\\1${release:-1}%{?dist}/" "$SPECS/$specfile"
        ok "spec version set to $version-${release:-1} (the spec shipped 'XXX', as DLRN expects)"
    fi
    # every other tracked file in the distgit is a Source/Patch
    local f n=0
    while IFS= read -r f; do
        case "$f" in *.spec) continue ;; esac
        install -D -m 0644 "$f" "$SRC/$(basename "$f")"
        n=$((n+1))
    done < <(find "$dir" -type f -not -path '*/.git/*' | sort)
    ok "spec + $n distgit source files staged"

    # tarballs.openstack.org groups by project name, which is the manifest's
    # last column: usually the package name, but oslo.limit publishes under a
    # dotted name while its tarball uses an underscore.
    # The name a spec expects is not always the name upstream publishes. PEP 625
    # made sdists use underscores (os_traits-3.6.0.tar.gz) while several specs
    # still build the old hyphenated filename from %{sname}. Rather than carry
    # that drift in the manifest, ask the spec what it wants: rpmspec -P expands
    # the macros, so Source0 comes back as a concrete filename.
    local wantname wantasc
    wantname="$(rpmspec -P "$SPECS/$specfile" 2>/dev/null \
        | awk '/^Source0:/ {print $2; exit}' | xargs -r basename)"
    [ -n "$wantname" ] || wantname="$tarball"
    wantasc="$(rpmspec -P "$SPECS/$specfile" 2>/dev/null \
        | awk '/^Source101:/ {print $2; exit}' | xargs -r basename)"
    [ -n "$wantasc" ] || wantasc="$wantname.asc"
    if [ "$wantname" != "$tarball" ]; then
        ok "spec expects $wantname; upstream publishes $tarball (PEP 625 naming drift)"
    fi

    fetch_pinned "https://tarballs.openstack.org/$urlproj/$tarball" "$SRC/$wantname" "$tsha"
    curl -sSfL -o "$SRC/$wantasc" "https://tarballs.openstack.org/$urlproj/$tarball.asc" \
        || die "the detached signature for $tarball could not be fetched"
    ok "detached signature fetched as $wantasc (verified by %gpgverify in %prep)"
    # Which key actually signed this tarball is a property of the RELEASE, not
    # of the spec. OpenStack rotates its release signing key every cycle, and a
    # stable point release made after a rotation is signed with the newer key —
    # 2026.1 needs two: glance and placement (released 2026-04) carry one,
    # keystone/neutron/nova/horizon (point releases 2026-09) carry another.
    # RDO's rpm-master spec pins a third key, which signed neither. So the
    # manifest names the key per package, and it is checked by fingerprint.
    local keyid keysha
    keyid="$(grep -m1 -E '^%global[[:space:]]+sources_gpg_sign' "$SPECS/$specfile" | awk '{print $3}')"
    if [ -z "$keyid" ]; then
        # Not every RDO spec verifies the upstream signature. That is the spec's
        # choice and not a failure here, but it does mean this tarball is trusted
        # on its sha256 alone — so say so rather than letting it pass quietly.
        printf '  NOTE  %s performs no GPG verification; this tarball is pinned by sha256 only\n' "$specfile"
    else
        if [ -n "$wantkey" ] && [ "$wantkey" != "-" ] && [ "$wantkey" != "$keyid" ]; then
            sed -i -E "s|^(%global[[:space:]]+sources_gpg_sign[[:space:]]+).*|\\1$wantkey|" "$SPECS/$specfile"
            ok "signing key retargeted: spec said ${keyid:0:14}…, this release was signed by ${wantkey:0:14}…"
            keyid="$wantkey"
        fi
        keysha="$(awk -v k="$keyid" '$1=="KEY" && $2==k {print $3}' "$MANIFEST" | head -1)"
        [ -n "$keysha" ] || die "the spec verifies against signing key $keyid, which the manifest does not pin.
     Add a line:  KEY $keyid <sha256>
     after checking the key yourself. Nothing unpinned is fetched."
        fetch_pinned "$KEY_BASE/$keyid.txt" "$SRC/$keyid.txt" "$keysha"
    fi

    local spec="$SPECS/$specfile"
    # PEP 625 renamed the sdists, and with them the directory they unpack into:
    # os_traits-3.6.0/ where the spec still says os-traits-3.6.0. Six packages hit
    # this. Rather than six near-identical patches, take the top-level directory
    # from the tarball itself and point %autosetup at it. Deterministic, and the
    # log says when it changed anything.
    local topdir cur
    topdir="$(tar tzf "$SRC/$wantname" 2>/dev/null | head -1 | cut -d/ -f1)"
    cur="$(grep -m1 -E '^%autosetup +-n ' "$SPECS/$specfile" | awk '{print $3}')"
    if [ -n "$topdir" ] && [ -n "$cur" ]; then
        sed -i -E "0,/^(%autosetup +-n +)[^ ]+/s//\\1$topdir/" "$SPECS/$specfile"
        local now; now="$(grep -m1 -E '^%autosetup +-n ' "$SPECS/$specfile" | awk '{print $3}')"
        [ "$now" = "$cur" ] || ok "%autosetup -n set to the tarball's actual directory: $topdir (spec said $cur)"
    fi

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
    local checkflag=""
    if [ "$NOCHECK" -eq 1 ]; then
        checkflag="--nocheck"
        log_nocheck="yes"
        printf '  NOTE  building with --nocheck: the test suite is NOT run for %s\n' "$pkg"
    fi
    # shellcheck disable=SC2086
    rpmbuild -bb $checkflag "$spec" > "$LOGDIR/$pkg.rpmbuild.log" 2>&1
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "rpmbuild exit=0"
        grep -aE "Good signature|gpgverify" "$LOGDIR/$pkg.rpmbuild.log" | head -3 | sed 's/^/      /'
        find "$RPMTOP/RPMS" -name "*.rpm" -newer "$spec" -printf '      %f\n' | sort
        if [ "$NOCHECK" -eq 1 ]; then
            RESULTS+=("PASS $pkg (built; %check NOT run)")
        else
            local ran; ran="$(grep -aoE '^Ran: [0-9]+ tests' "$LOGDIR/$pkg.rpmbuild.log" | tail -1)"
            if [ -n "$ran" ]; then RESULTS+=("PASS $pkg (${ran})")
            else RESULTS+=("PASS $pkg (built; the spec ran no %check)"); fi
        fi
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
    # Where the repository lives. Defaults to this build's own output, but a
    # builder that is adding packages to an EXISTING release repository must
    # point this at that directory — otherwise the published repo file is
    # rewritten to contain only what this run built, and every package from
    # earlier runs silently disappears from dnf's view.
    local repodir="${REPO_PUBLISH_DIR:-$RPMTOP/RPMS}" names=() n
    command -v createrepo_c >/dev/null || { bad "createrepo_c is not installed; cannot publish"; return 1; }
    # The repository may be root-owned when it is a shared release tree rather
    # than this user's own output, so fall back to sudo rather than failing.
    createrepo_c --quiet "$repodir" >/dev/null 2>&1 \
        || sudo createrepo_c --quiet "$repodir" >/dev/null 2>&1 \
        || { bad "createrepo_c failed on $repodir"; return 1; }

    # The repository is named after the manifest, so a repo called
    # hagistack-gazpacho cannot be mistaken for a 2025.1 build. The old name
    # (hagistack-epoxy) is removed if present, so an upgraded builder does not
    # end up serving the same RPMs twice under two ids.
    local repoid="hagistack-$(basename "$MANIFEST" .manifest)"
    sudo rm -f /etc/yum.repos.d/hagistack-epoxy.repo
    sudo tee "/etc/yum.repos.d/$repoid.repo" >/dev/null <<EOF
# Self-built OpenStack RPMs for Rocky Linux 10, produced by build-rpms.sh from
# the pinned inputs in $(basename "$MANIFEST").
# priority=1 so these win over RDO's centos10-master trunk builds.
[$repoid]
name=hagistack self-built OpenStack from $(basename "$MANIFEST") (Rocky 10)
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
    ok "published $repodir as [$repoid] (priority=1)"
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

while read -r pkg repo commit specfile version release tarball tsha urlproj signkey _rest; do
    case "$pkg" in ''|\#*|KEY) continue ;; esac
    # PYPI <rpm-name> <pypi-name> <version> <sdist> <sha256> <license> <summary...>
    if [ "$pkg" = "PYPI" ]; then
        if [ ${#WANT[@]} -gt 0 ]; then
            printf '%s\n' "${WANT[@]}" | grep -qx "$repo" || continue
        fi
        build_pypi "$repo" "$commit" "$specfile" "$version" "$release" "$tarball" \
                   "$tsha $urlproj $signkey $_rest"
        continue
    fi
    if [ ${#WANT[@]} -gt 0 ]; then
        printf '%s\n' "${WANT[@]}" | grep -qx "$pkg" || continue
    fi
    build_one "$pkg" "$repo" "$commit" "$specfile" "$version" "$release" \
              "$tarball" "$tsha" "${urlproj:-$pkg}" "${signkey:-}"
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
