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
#
# Runs on Rocky/EL (needs rpm, tar, sha256sum, python3). Exits non-zero on any
# failed check; a candidate that fails a check is not written.
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
        -h|--help)  sed -n '2,26p' "$0"; exit 0 ;;
        *) die "unknown option $1" ;;
    esac
done
[ -n "$SET_DIR" ] && [ -n "$TAG" ] && [ -n "$OUT" ] || die "--set-dir, --tag and --out are required"
[[ "$TAG" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "--tag has characters a release tag cannot have"
[[ "$BASE_URL" =~ ^https?://[A-Za-z0-9._~:/@+=-]+$ ]] || die "--base-url is not a plain http(s) URL"
for t in rpm tar sha256sum python3; do command -v "$t" >/dev/null || die "$t is required"; done
[ -f "$SET_DIR/RPM-SHA256SUMS" ] && [ -d "$SET_DIR/repo/repodata" ] || die "$SET_DIR is not a verified set directory"
[ ! -e "$OUT" ] || [ -z "$(ls -A "$OUT")" ] || die "$OUT exists and is not empty"
# The MIT licence of Hagistack's own work and the notices must ship with every
# candidate. LICENSE is the repository-root file, so run this from a full checkout.
for f in "$HERE/../LICENSE" "$HERE/THIRD_PARTY_NOTICES.md" "$HERE/gazpacho.manifest"; do
    [ -f "$f" ] || die "$f is missing: run from a full checkout (every candidate must carry it)"
done
[ -d "$HERE/third-party" ] || die "$HERE/third-party is missing: run from a full checkout"
mkdir -p "$OUT"

echo "== checking the set =="
# The same listing hagistack verifies: every RPM present, listed, unaltered.
( cd "$SET_DIR/repo" && find . -maxdepth 1 -name '*.rpm' -printf '%f\n' | LC_ALL=C sort \
    | while IFS= read -r n; do printf '%s  %s\n' "$(sha256sum "$n" | cut -d' ' -f1)" "$n"; done ) > "$OUT/.sums"
cmp -s "$OUT/.sums" "$SET_DIR/RPM-SHA256SUMS" || die "the RPMs do not match RPM-SHA256SUMS"
rm -f "$OUT/.sums"
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
extra="$(cd "$SET_DIR/srpms" && find . -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort \
         | comm -23 - <(awk -F'\t' 'NR>1{print $8}' "$OUT/PACKAGE_MANIFEST.tsv" | LC_ALL=C sort -u))"
[ -z "$extra" ] || die "srpms/ holds files no binary RPM comes from (would be published): $extra"
# Every source RPM carries Hagistack's own licence for the packaging it contains.
# (the list is captured first: with pipefail, "rpm | grep -q" can fail on SIGPIPE)
nolic="$(cd "$SET_DIR/srpms" && for s in ./*.src.rpm; do
             l="$(rpm -qpl --nosignature "$s" 2>/dev/null || true)"
             grep -qx 'HAGISTACK-LICENSE' <<<"$l" || echo "${s#./}"; done)"
[ -z "$nolic" ] || die "source RPMs without HAGISTACK-LICENSE: $nolic"
ok "srpms/ holds exactly the set's source RPMs, each with HAGISTACK-LICENSE"

# Deterministic tarballs: same set, same bytes, whatever the clock says.
EPOCH="$(stat -c %Y "$SET_DIR/RPM-SHA256SUMS")"
TFLAGS=(--sort=name --owner=0 --group=0 --numeric-owner --mtime="@$EPOCH" --format=gnu)
ASSET="hagistack-rpms-$TAG-el10-x86_64.tar"
tar -cf "$OUT/$ASSET" "${TFLAGS[@]}" -C "$SET_DIR" RPM-SHA256SUMS repo
tar -cf "$OUT/hagistack-srpms-$TAG.tar" "${TFLAGS[@]}" -C "$SET_DIR" srpms
ok "assets written"

cp -p "$HERE/gazpacho.manifest" "$OUT/"
cp -p "$HERE/../LICENSE" "$OUT/LICENSE"
[ -f "$SET_DIR/build-env.lock" ] && cp -p "$SET_DIR/build-env.lock" "$OUT/"
cp -rp "$HERE/third-party" "$OUT/third-party"
cp -p "$HERE/THIRD_PARTY_NOTICES.md" "$OUT/"

ASHA="$(sha256sum "$OUT/$ASSET" | cut -d' ' -f1)"
ASIZE="$(stat -c %s "$OUT/$ASSET")"
MSHA="$(sha256sum "$HERE/gazpacho.manifest" | cut -d' ' -f1)"
cat > "$OUT/rpm-release.lock.candidate" <<EOF
# Candidate lock for release $TAG, written by make-rpm-release.sh.
# Commit it as rocky10.2/rpm-release.lock ONLY after the release is published
# and audited. Until then it must not be used as the default lock.
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
echo
echo "asset  : $ASSET ($ASIZE bytes)"
echo "sha256 : $ASHA"
echo "set    : $SET_SHA ($COUNT RPMs)"
echo "Nothing was published."
