#!/usr/bin/env bash
# make-rpm-release.sh — turn a verified RPM set into GitHub Release candidate files.
#
#   ./make-rpm-release.sh --set-dir DIR --tag TAG --out DIR [--base-url URL]
#
# DIR is a set directory as `hagistack --rpm-source build` leaves it
# (/var/lib/hagistack/rpm-build/<id>/out): RPM-SHA256SUMS, repo/ (RPMs and
# repodata), srpms/, build-env.lock, logs/.
#
# It PREPARES files locally. It publishes nothing, creates no tag and no
# release, and pushes nothing: publication is a separate, human decision made
# after the licence audit and an independent audit.
#
# Output (in --out):
#   hagistack-rpms-<TAG>-el10-x86_64.tar   the asset --rpm-source github installs
#   hagistack-srpms-<TAG>.tar              the corresponding source RPMs
#   PACKAGE_MANIFEST.tsv                   one line per RPM: NEVRA, licence, source RPM, sha256
#   SHA256SUMS                             of every file above (informational: the
#                                          trust anchor is rpm-release.lock, not this)
#   rpm-release.lock.candidate             the lock to commit IF this is published
#   gazpacho.manifest, build-env.lock, LICENSE, third-party/   provenance
#   THIRD_PARTY_NOTICES.md                 which licence covers what
#   RELEASE-README.md                      contents, supported systems, install, limits
#
# Runs on Rocky/EL (needs rpm, rpm2cpio, tar, sha256sum, python3, realpath) from
# a full checkout; in a git work tree the files it ships must be committed.
# Exits non-zero on any failed check. A failed check before the assets stops
# before they and the lock are written; one after them stops before the lock;
# the final check of the whole candidate runs after the lock and SHA256SUMS are
# written. Whenever it exits non-zero, --out may hold partial files: discard it.
set -euo pipefail

die(){ printf 'STOP: %s\n' "$*" >&2; exit 1; }
ok(){  printf '  ok    %s\n' "$*"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
SET_DIR=""; TAG=""; OUT=""; BASE_URL="https://github.com/hagix9/hagistack/releases/download"
EXPECT_BUILDHOST="hagistack-builder"
while [ $# -gt 0 ]; do
    case "$1" in
        --set-dir)  SET_DIR="${2:-}"; shift 2 ;;
        --tag)      TAG="${2:-}"; shift 2 ;;
        --out)      OUT="${2:-}"; shift 2 ;;
        --base-url) BASE_URL="${2:-}"; shift 2 ;;
        -h|--help)  sed -n '2,29p' "$0"; exit 0 ;;
        *) die "unknown option $1" ;;
    esac
done
[ -n "$SET_DIR" ] && [ -n "$TAG" ] && [ -n "$OUT" ] || die "--set-dir, --tag and --out are required"
[[ "$TAG" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "--tag has characters a release tag cannot have"
[[ "$BASE_URL" =~ ^https?://[A-Za-z0-9._~:/@+=-]+$ ]] || die "--base-url is not a plain http(s) URL"
for t in rpm rpm2cpio tar sha256sum python3 realpath; do command -v "$t" >/dev/null || die "$t is required"; done
[ -f "$SET_DIR/RPM-SHA256SUMS" ] && [ -d "$SET_DIR/repo/repodata" ] || die "$SET_DIR is not a verified set directory"
[ -f "$SET_DIR/build-env.lock" ] || die "$SET_DIR/build-env.lock is missing (every candidate carries it)"
SET_DIR="$(realpath -e -- "$SET_DIR")" || die "cannot resolve --set-dir"
OUT="$(realpath -m -- "$OUT")" || die "cannot resolve --out"
# The assets are made from SET_DIR: --out inside it would end up in them.
case "$OUT/" in "$SET_DIR"/*) die "--out must be outside --set-dir" ;; esac
case "$SET_DIR/" in "$OUT"/*) die "--set-dir must be outside --out" ;; esac
[ ! -e "$OUT" ] || [ -z "$(ls -A "$OUT")" ] || die "$OUT exists and is not empty"
# The MIT licence of Hagistack's own work and the notices must ship with every
# candidate. LICENSE is the repository-root file, so run this from a full checkout.
for f in "$HERE/../LICENSE" "$HERE/THIRD_PARTY_NOTICES.md" "$HERE/gazpacho.manifest" \
         "$HERE/RELEASE-README.md" "$HERE/release_check.py" "$HERE/hagistack"; do
    [ -f "$f" ] && [ ! -L "$f" ] || die "$f is missing: run from a full checkout (every candidate must carry it)"
done
[ -d "$HERE/third-party" ] && [ ! -L "$HERE/third-party" ] || die "$HERE/third-party is missing: run from a full checkout"
BRAND_DIR="$HERE/packaging/files/python-django-horizon"
DOCS_BRAND_DIR="$HERE/packaging/files/_docs-branding"
for d in "$BRAND_DIR" "$DOCS_BRAND_DIR"; do
    [ -d "$d" ] && [ ! -L "$d" ] || die "$d is missing: run from a full checkout"
done
# third-party/ is shipped as it is: exactly the files the notices describe, the
# pinned ones (LICENSE and PATCH rows of gazpacho.manifest) unaltered.
odd="$(cd "$HERE" && find third-party -mindepth 1 ! -type f ! -type d -printf '%p\n')"
[ -z "$odd" ] || die "third-party/ holds something that is not a plain file: $odd"
want_tp="$( { awk '$1=="LICENSE"||$1=="PATCH"{print $3}' "$HERE/gazpacho.manifest"
              printf '%s\n' third-party/licenses/NOTICE.md third-party/neutron/LICENSE third-party/neutron/NOTICE.md; } | LC_ALL=C sort)"
have_tp="$(cd "$HERE" && find third-party -type f -printf '%p\n' | LC_ALL=C sort)"
[ "$want_tp" = "$have_tp" ] || die "third-party/ does not hold exactly the expected files:
$(diff <(printf '%s\n' "$want_tp") <(printf '%s\n' "$have_tp") | grep '^[<>]' || true)"
while read -r _ _ rel sha; do
    [ "$(sha256sum "$HERE/$rel" | cut -d' ' -f1)" = "$sha" ] || die "$rel differs from its pin in gazpacho.manifest"
done < <(awk '$1=="LICENSE"||$1=="PATCH"' "$HERE/gazpacho.manifest")
# third-party/neutron/NOTICE.md names this text: the canonical Apache-2.0 file.
[ "$(sha256sum "$HERE/third-party/neutron/LICENSE" | cut -d' ' -f1)" = cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30 ] \
    || die "third-party/neutron/LICENSE is not the canonical Apache-2.0 text"
# In a git work tree, what is shipped (and the checks themselves) must be committed.
if command -v git >/dev/null && git -C "$HERE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dirty="$(git -C "$HERE" status --porcelain --ignored -- ../LICENSE THIRD_PARTY_NOTICES.md \
             gazpacho.manifest RELEASE-README.md third-party make-rpm-release.sh release_check.py hagistack \
             packaging/files/python-django-horizon packaging/files/_docs-branding)"
    [ -z "$dirty" ] || die "files this candidate ships or runs are not committed:
$dirty"
    ok "shipped files committed at $(git -C "$HERE" rev-parse --short HEAD)"
elif [ -e "$HERE/../.git" ]; then
    die "$HERE/.. is a git checkout, but git cannot read it (not installed, or not trusted): cannot check that the shipped files are committed"
else
    echo "  note  not a git work tree: the shipped files are checked by their pins only"
fi
mkdir -p "$OUT"

echo "== checking the set =="
# The same listing hagistack verifies: every RPM present, listed, unaltered.
( cd "$SET_DIR/repo" && find . -maxdepth 1 -name '*.rpm' -printf '%f\n' | LC_ALL=C sort \
    | while IFS= read -r n; do printf '%s  %s\n' "$(sha256sum "$n" | cut -d' ' -f1)" "$n"; done ) > "$OUT/.sums"
cmp -s "$OUT/.sums" "$SET_DIR/RPM-SHA256SUMS" || die "the RPMs do not match RPM-SHA256SUMS"
rm -f "$OUT/.sums"
# repo/ is published whole: it must hold nothing but those RPMs and repodata
# that describes exactly them.
msg="$(python3 -I "$HERE/release_check.py" repo "$SET_DIR")" || die "$msg"
ok "repo/ holds only the listed RPMs; repodata lists exactly them, checksums match"
SET_SHA="$(sha256sum "$SET_DIR/RPM-SHA256SUMS" | cut -d' ' -f1)"
COUNT="$(wc -l < "$SET_DIR/RPM-SHA256SUMS" | tr -d ' ')"
ok "$COUNT RPMs, set identity $SET_SHA"

# Publication hygiene: an RPM header records the build host. It must be the
# neutral name, never a cloud-internal FQDN that names a project or account.
bad="$(cd "$SET_DIR/repo" && rpm -qp --nosignature --qf '%{BUILDHOST} %{NAME}\n' ./*.rpm 2>/dev/null \
       | awk -v want="$EXPECT_BUILDHOST" '$1 != want' | head -5)"
[ -z "$bad" ] || die "RPM headers carry an unexpected BUILDHOST (would be published):
$bad"
ok "every RPM header says BUILDHOST=$EXPECT_BUILDHOST"

# Licence hygiene, checked on the RPMs themselves so a regression cannot ship:
#   * openstack-dashboard must not carry the build-time copies of the XStatic
#     libraries or the bundles made from them (spec-adapt rule 'horizon');
#   * every RPM a LICENSE row names must install that licence file.
dash="$(cd "$SET_DIR/repo" && ls openstack-dashboard-[0-9]*.rpm 2>/dev/null | head -1 || true)"
[ -n "$dash" ] || die "openstack-dashboard is not in the set"
leak="$(rpm -qpl --nosignature "$SET_DIR/repo/$dash" 2>/dev/null \
        | grep -E '/static/horizon/lib/|/static/dashboard/(js/output\.|css/output\.|manifest\.json)' | head -3 || true)"
[ -z "$leak" ] || die "$dash still ships third-party static copies:
$leak"
ok "$dash ships no copy of the XStatic libraries"
while read -r _ rpmname rel _; do
    f="$(cd "$SET_DIR/repo" && ls "$rpmname"-[0-9]*.rpm 2>/dev/null | head -1 || true)"
    [ -n "$f" ] || die "$rpmname (LICENSE row) is not in the set"
    lst="$(rpm -qpL --nosignature "$SET_DIR/repo/$f" 2>/dev/null || true)"
    grep -q "/$(basename "$rel")\$" <<<"$lst" \
        || die "$f does not install its licence file $(basename "$rel")"
done < <(awk '$1=="LICENSE"' "$HERE/gazpacho.manifest")
ok "every LICENSE row's RPM installs its licence file"

echo "== package manifest =="
{
    printf 'file\tname\tepoch\tversion\trelease\tarch\tlicense\tsourcerpm\tsha256\n'
    while read -r sha n; do
        rpm -qp --nosignature --qf "$n\t%{NAME}\t%{EPOCHNUM}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\t%{LICENSE}\t%{SOURCERPM}\t$sha\n" \
            "$SET_DIR/repo/$n" 2>/dev/null
    done < "$SET_DIR/RPM-SHA256SUMS"
} > "$OUT/PACKAGE_MANIFEST.tsv"
ok "PACKAGE_MANIFEST.tsv: $(($(wc -l < "$OUT/PACKAGE_MANIFEST.tsv") - 1)) lines"

# Every binary's source RPM must be in srpms/, so the source offer is complete.
missing="$(awk -F'\t' 'NR>1{print $8}' "$OUT/PACKAGE_MANIFEST.tsv" | sort -u \
           | while read -r s; do [ -f "$SET_DIR/srpms/$s" ] || echo "$s"; done)"
[ -z "$missing" ] || die "source RPMs missing for: $missing"
ok "every binary RPM has its source RPM"
# ... and srpms/ holds nothing else, so the source asset is exactly the set's sources.
odd="$(cd "$SET_DIR/srpms" && find . -mindepth 1 \( ! -type f -o -path './*/*' \) -printf '%P\n')"
[ -z "$odd" ] || die "srpms/ holds something that is not a plain file (would be published): $odd"
extra="$(cd "$SET_DIR/srpms" && find . -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort \
         | comm -23 - <(awk -F'\t' 'NR>1{print $8}' "$OUT/PACKAGE_MANIFEST.tsv" | LC_ALL=C sort -u))"
[ -z "$extra" ] || die "srpms/ holds files no binary RPM comes from (would be published): $extra"
# Each binary was built from exactly that source RPM, not one with its name:
# the binary's SOURCEPKGID is the source RPM's header digest (SIGMD5).
declare -A SIGMD5=()
for s in "$SET_DIR"/srpms/*.src.rpm; do
    SIGMD5["${s##*/}"]="$(rpm -qp --nosignature --qf '%{SIGMD5}' "$s" 2>/dev/null)" || die "rpm cannot read ${s##*/}"
done
while read -r n; do
    read -r srpm pkgid < <(rpm -qp --nosignature --qf '%{SOURCERPM} %{SOURCEPKGID}\n' "$SET_DIR/repo/$n" 2>/dev/null) \
        || die "rpm cannot read $n"
    [ -n "${SIGMD5[$srpm]:-}" ] && [ "$pkgid" = "${SIGMD5[$srpm]}" ] \
        || die "$n was not built from the $srpm in srpms/ (SOURCEPKGID $pkgid)"
done < <(cut -d' ' -f3- "$SET_DIR/RPM-SHA256SUMS")
# Every source RPM carries Hagistack's own licence for the packaging it contains,
# byte for byte the LICENSE shipped with the candidate.
for s in "$SET_DIR"/srpms/*.src.rpm; do
    msg="$(python3 -I "$HERE/release_check.py" licence "$s" "$HERE/../LICENSE")" || die "$msg"
done
ok "srpms/ holds exactly the set's source RPMs (header digests match), each with HAGISTACK-LICENSE = LICENSE"
# Hagistack's changes to upstream sources are stated inside the RPMs: each binary
# of a source RPM that declares changes installs HAGISTACK-CHANGES as its spec
# writes it, and its changelog lists them.
msg="$(python3 -I "$HERE/release_check.py" notices "$SET_DIR")" || die "$msg"
ok "every binary of a source RPM with changes to upstream installs HAGISTACK-CHANGES"
# The dashboard and the HTML documentation show Hagistack's logo: no RPM carries
# an OpenStack-logo image (Horizon's or the documentation theme's), and
# Hagistack's images are at each place they replace.
msg="$(python3 -I "$HERE/release_check.py" branding "$SET_DIR" "$BRAND_DIR" "$DOCS_BRAND_DIR")" || die "$msg"
ok "no RPM carries an OpenStack-logo image; the dashboard and every HTML documentation tree carry Hagistack's"

# Deterministic tarballs: same set, same bytes, whatever the clock says.
EPOCH="$(stat -c %Y "$SET_DIR/RPM-SHA256SUMS")"
TFLAGS=(--sort=name --owner=0 --group=0 --numeric-owner --mtime="@$EPOCH" --format=gnu)
ASSET="hagistack-rpms-$TAG-el10-x86_64.tar"
tar -cf "$OUT/$ASSET" "${TFLAGS[@]}" -C "$SET_DIR" RPM-SHA256SUMS repo
tar -cf "$OUT/hagistack-srpms-$TAG.tar" "${TFLAGS[@]}" -C "$SET_DIR" srpms
# Check what was written, not only what was meant: exactly the expected members,
# and the asset passes the very member check the installer applies before unpacking.
{ echo RPM-SHA256SUMS; cut -d' ' -f3- "$SET_DIR/RPM-SHA256SUMS" | sed 's|^|repo/|'
  ( cd "$SET_DIR/repo/repodata" && find . -maxdepth 1 -type f -printf 'repo/repodata/%f\n' ); } > "$OUT/.members"
msg="$(python3 -I "$HERE/release_check.py" members "$OUT/$ASSET" "$OUT/.members")" || die "$msg"
( cd "$SET_DIR/srpms" && find . -maxdepth 1 -type f -printf 'srpms/%f\n' ) > "$OUT/.members"
msg="$(python3 -I "$HERE/release_check.py" members "$OUT/hagistack-srpms-$TAG.tar" "$OUT/.members")" || die "$msg"
rm -f "$OUT/.members"
TAR_CHECK_PY="$(env -i PATH="$PATH" HAGISTACK_LIB_ONLY=1 bash -c 'source "$1" >/dev/null 2>&1 && printf %s "$TAR_CHECK_PY"' _ "$HERE/hagistack")"
[ -n "$TAR_CHECK_PY" ] || die "cannot read the installer's member check from $HERE/hagistack"
msg="$(python3 -I -c "$TAR_CHECK_PY" "$OUT/$ASSET" 2>&1)" || die "the installer would refuse $ASSET: $msg"
[ "$msg" = "$((COUNT + 1 + $(find "$SET_DIR/repo/repodata" -maxdepth 1 -type f | wc -l)))" ] \
    || die "the installer's member check counted $msg members in $ASSET"
ok "assets written; members exactly as expected; the installer's member check accepts $ASSET"

cp -p "$HERE/gazpacho.manifest" "$OUT/"
cp -p "$HERE/../LICENSE" "$OUT/LICENSE"
cp -p "$SET_DIR/build-env.lock" "$OUT/"
cp -rp "$HERE/third-party" "$OUT/third-party"
cp -p "$HERE/THIRD_PARTY_NOTICES.md" "$OUT/"
cp -p "$HERE/RELEASE-README.md" "$OUT/"

ASHA="$(sha256sum "$OUT/$ASSET" | cut -d' ' -f1)"
ASIZE="$(stat -c %s "$OUT/$ASSET")"
MSHA="$(sha256sum "$HERE/gazpacho.manifest" | cut -d' ' -f1)"
cat > "$OUT/rpm-release.lock.candidate" <<EOF
# Candidate lock for release $TAG, written by make-rpm-release.sh.
# Publication order, once the candidate is audited and the Owner approves:
# commit this file as rocky10.2/rpm-release.lock, tag that commit $TAG, then
# create the release from the tag and upload the candidate's files. Never commit
# it for a candidate that will not be published.
LOCK_FORMAT=1
LOCK_STATUS=published
RELEASE_TAG=$TAG
BASE_URL=$BASE_URL
ASSET_NAME=$ASSET
ASSET_SHA256=$ASHA
ASSET_SIZE=$ASIZE
RPM_SET_SHA256=$SET_SHA
RPM_COUNT=$COUNT
MANIFEST_SHA256=$MSHA
EOF
( cd "$OUT" && find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' sha256sum ) > "$OUT/SHA256SUMS"
ok "rpm-release.lock.candidate and SHA256SUMS written"
# The candidate is exactly the standard set of files, and SHA256SUMS covers each.
want_out="$(printf '%s\n' "$ASSET" "hagistack-srpms-$TAG.tar" PACKAGE_MANIFEST.tsv SHA256SUMS \
    rpm-release.lock.candidate LICENSE THIRD_PARTY_NOTICES.md RELEASE-README.md gazpacho.manifest \
    build-env.lock third-party | LC_ALL=C sort)"
have_out="$(cd "$OUT" && find . -mindepth 1 -maxdepth 1 -printf '%P\n' | LC_ALL=C sort)"
[ "$want_out" = "$have_out" ] || die "the candidate does not hold exactly the standard files:
$(diff <(printf '%s\n' "$want_out") <(printf '%s\n' "$have_out") | grep '^[<>]' || true)"
odd="$(cd "$OUT" && find . -mindepth 1 ! -type f ! -type d -printf '%P\n')"
[ -z "$odd" ] || die "the candidate holds something that is not a plain file: $odd"
[ "$(cd "$OUT" && find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort)" = "$(cut -d' ' -f3- "$OUT/SHA256SUMS")" ] \
    || die "SHA256SUMS does not list exactly the candidate's files"
( cd "$OUT" && sha256sum -c --quiet SHA256SUMS ) || die "SHA256SUMS does not verify"
ok "the candidate holds exactly the standard files; SHA256SUMS lists and verifies each"
echo
echo "asset  : $ASSET ($ASIZE bytes)"
echo "sha256 : $ASHA"
echo "set    : $SET_SHA ($COUNT RPMs)"
echo "Nothing was published."
