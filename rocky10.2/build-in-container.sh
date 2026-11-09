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

# Paths are variables only so that tests can point them at a scratch tree;
# hagistack always uses the defaults.
SRC_DIR="${BIC_SRC:-/src}"
BUILD_DIR="${BIC_BUILD:-/build}"
OUT_DIR="${BIC_OUT:-/out}"
LOG_DIR="$OUT_DIR/logs"

# ---------------------------------------------------------------------------
# What a complete build is, and how a pass result is judged.
#
# The rules, all of which fail closed:
#   * every pass's exit status is taken explicitly;
#   * a STOP in a pass (a pin, digest or signature failed, or a fetch failed)
#     ends the build at once and is never retried;
#   * a pass's results file must exist, be non-empty, contain only
#     "PASS|FAIL <name> (<detail>)" lines, name each expected package exactly
#     once and nothing else — otherwise the pass is treated as broken;
#   * the exit status and the results must agree (0 <=> no FAIL);
#   * only build-dependency failures (rpmbuild exit 11 with "is needed by" in
#     that package's log) go to pass 2 — the recorded case where the manifest
#     lists services before the 2026.1 libraries they need. Any other failure
#     ends the build;
#   * pass 2 must build every one of those packages; the build is complete only
#     when every manifest package has a PASS, and only then is build.ok written.
# ---------------------------------------------------------------------------

# The packages build-rpms.sh will build from a manifest, in its own terms:
# the first column, the rpm name for PYPI rows; KEY/SPEC/PATCH/LICENSE rows
# and comments (including #DISABLED rows) are not packages.
expected_packages() {   # expected_packages <manifest>
    awk '$0 ~ /^[[:space:]]*($|#)/ {next}
         $1=="KEY" || $1=="SPEC" || $1=="PATCH" || $1=="LICENSE" {next}
         $1=="PYPI" {print $2; next}
         {print $1}' "$1"
}

RESULT_LINE_RE='^(PASS|FAIL) [A-Za-z0-9._+-]+ \(.+\)$'

# check_results <results-file> <expected name...>
check_results() {
    local f="$1"; shift
    [ -f "$f" ] || { echo "results file $f is missing" >&2; return 1; }
    [ -s "$f" ] || { echo "results file $f is empty" >&2; return 1; }
    local bad
    bad="$(grep -vcE "$RESULT_LINE_RE" "$f" || true)"
    [ "${bad:-0}" -eq 0 ] || { echo "results file $f has $bad malformed line(s)" >&2; return 1; }
    local dup
    dup="$(awk '{print $2}' "$f" | sort | uniq -d | head -3 | tr '\n' ' ')"
    [ -z "$dup" ] || { echo "results file $f names a package twice: $dup" >&2; return 1; }
    local have want missing extra
    have="$(awk '{print $2}' "$f" | LC_ALL=C sort)"
    want="$(printf '%s\n' "$@" | LC_ALL=C sort)"
    missing="$(LC_ALL=C comm -13 <(printf '%s\n' "$have") <(printf '%s\n' "$want") | tr '\n' ' ')"
    extra="$(LC_ALL=C comm -23 <(printf '%s\n' "$have") <(printf '%s\n' "$want") | tr '\n' ' ')"
    [ -z "${missing// /}" ] || { echo "results file $f is incomplete; no result for: $missing" >&2; return 1; }
    [ -z "${extra// /}" ] || { echo "results file $f names packages that were not asked for: $extra" >&2; return 1; }
    return 0
}

failed_in() { awk '$1=="FAIL"{print $2}' "$1"; }

# Prints the FAILed packages that are build-dependency failures; returns 1
# (and names them on stderr) if any FAIL is something else.
retryable_failures() {   # retryable_failures <results-file> <package-log-dir>
    local f="$1" logs="$2" line name code other=""
    while IFS= read -r line; do
        [[ "$line" == FAIL\ * ]] || continue
        name="$(awk '{print $2}' <<<"$line")"
        code="$(grep -oE 'rpmbuild exit [0-9]+' <<<"$line" | awk '{print $3}')"
        if [ "$code" = "11" ] && grep -q 'is needed by' "$logs/$name.rpmbuild.log" 2>/dev/null; then
            printf '%s\n' "$name"
        else
            other="$other $name(${code:-no rpmbuild exit})"
        fi
    done < "$f"
    [ -z "$other" ] || { echo "not a build-dependency failure:$other" >&2; return 1; }
    return 0
}

stopped_in() { grep -q '^STOP' "$1" 2>/dev/null; }

# A results file per pass, so the second pass rebuilds only what failed.
run_pass() {   # run_pass <n> [package ...]  -> build-rpms.sh's exit status
    local n="$1"; shift
    say "build pass $n${*:+: $*}"
    local rc=0
    ( cd "$SRC_DIR" && RESULTS_FILE="$LOG_DIR/pass$n.results" BUILD_SRPMS=1 \
        ./build-rpms.sh --nocheck "$@" ) > "$LOG_DIR/pass$n.log" 2>&1 || rc=$?
    tail -n 80 "$LOG_DIR/pass$n.log" | grep -E '^  (PASS|FAIL)|STOP' || true
    return "$rc"
}

# Pass 1 builds everything; pass 2 only the build-dependency failures of pass 1
# (build-rpms.sh publishes what did build at priority=1 at the end of pass 1,
# which is exactly what those packages were missing). The recorded two-pass
# procedure, automated — not a retry loop.
build_all() {   # build_all <manifest>
    local manifest="$1" expected rc1=0 rc2=0 fails retry reason
    mapfile -t expected < <(expected_packages "$manifest")
    [ "${#expected[@]}" -gt 0 ] || die "no packages found in $manifest"

    run_pass 1 || rc1=$?
    if stopped_in "$LOG_DIR/pass1.log"; then
        grep '^STOP' -A4 "$LOG_DIR/pass1.log" >&2
        die "pass 1 stopped on a verification or fetch failure (exit $rc1); nothing is retried after a STOP"
    fi
    reason="$(check_results "$LOG_DIR/pass1.results" "${expected[@]}" 2>&1)" \
        || die "pass 1 (exit $rc1) did not produce a usable result: $reason"
    fails="$(failed_in "$LOG_DIR/pass1.results" | tr '\n' ' ')"
    if [ "$rc1" -eq 0 ] && [ -n "${fails// /}" ]; then
        die "pass 1 exited 0 but its results list failures: $fails"
    fi
    if [ "$rc1" -ne 0 ] && [ -z "${fails// /}" ]; then
        die "pass 1 exited $rc1 but its results list no failure; refusing to guess what happened"
    fi

    if [ -n "${fails// /}" ]; then
        retry="$(retryable_failures "$LOG_DIR/pass1.results" "$BUILD_DIR/work/logs" 2>"$LOG_DIR/.retry.err")" \
            || die "pass 1 failed for a reason a second pass cannot fix ($(cat "$LOG_DIR/.retry.err")); not retried"
        # shellcheck disable=SC2086
        run_pass 2 $retry || rc2=$?
        if stopped_in "$LOG_DIR/pass2.log"; then
            grep '^STOP' -A4 "$LOG_DIR/pass2.log" >&2
            die "pass 2 stopped on a verification or fetch failure (exit $rc2)"
        fi
        # shellcheck disable=SC2086
        reason="$(check_results "$LOG_DIR/pass2.results" $retry 2>&1)" \
            || die "pass 2 (exit $rc2) did not produce a usable result: $reason"
        local still; still="$(failed_in "$LOG_DIR/pass2.results" | tr '\n' ' ')"
        [ -z "${still// /}" ] || die "these packages failed in both passes: $still (logs: $LOG_DIR, $BUILD_DIR/work/logs)"
        [ "$rc2" -eq 0 ] || die "pass 2 exited $rc2 although every package reports PASS; refusing to trust it"
    fi

    # Every manifest package must have a PASS in one of the two passes.
    local p
    for p in "${expected[@]}"; do
        # pass2.results exists only when a second pass ran.
        local f found=0
        for f in "$LOG_DIR/pass1.results" "$LOG_DIR/pass2.results"; do
            [ -f "$f" ] || continue
            awk -v p="$p" '$1=="PASS" && $2==p {ok=1} END {exit !ok}' "$f" && found=1
        done
        [ "$found" -eq 1 ] || die "no successful build recorded for $p"
    done
    EXPECTED_COUNT="${#expected[@]}"
    return 0
}

# Copy the result out. Every package builds exactly one source RPM, so the
# number of SRPMs must equal the number of manifest packages: fewer means a
# package is missing from the set, and the set is not complete.
collect_result() {
    say "collecting the result"
    # Copy, never move: /build keeps its rpmbuild tree so a later run can reuse it.
    rm -rf "$OUT_DIR/repo" "$OUT_DIR/srpms"; mkdir -p "$OUT_DIR/repo" "$OUT_DIR/srpms"
    find "$BUILD_DIR/rpmbuild/RPMS" -name '*.rpm' -exec cp -p {} "$OUT_DIR/repo/" \;
    find "$BUILD_DIR/rpmbuild/SRPMS" -name '*.src.rpm' -exec cp -p {} "$OUT_DIR/srpms/" \;
    local nrpm nsrpm
    nrpm="$(find "$OUT_DIR/repo" -name '*.rpm' | wc -l)"
    nsrpm="$(find "$OUT_DIR/srpms" -name '*.src.rpm' | wc -l)"
    [ "$nrpm" -gt 0 ] || die "the build produced no binary RPM"
    [ "$nsrpm" -eq "$EXPECTED_COUNT" ] \
        || die "$nsrpm source RPMs for $EXPECTED_COUNT manifest packages: the RPM set is incomplete"
    # gzip metadata on purpose: hagistack verifies repodata with the Python
    # standard library on the node, which reads gzip but has no zstd.
    createrepo_c --quiet --general-compress-type=gz "$OUT_DIR/repo" \
        || die "createrepo_c failed on $OUT_DIR/repo"
    cp -p "$BUILD_DIR/work/build-env.lock" "$OUT_DIR/build-env.lock" 2>/dev/null || true
    cp -rp "$BUILD_DIR/work/logs" "$LOG_DIR/packages" 2>/dev/null || true
    printf '%s RPMs, %s SRPMs\n' "$nrpm" "$nsrpm"
    # Written last: hagistack accepts the set only when this file exists.
    printf 'packages=%s rpms=%s srpms=%s\n' "$EXPECTED_COUNT" "$nrpm" "$nsrpm" > "$LOG_DIR/build.ok"
}

[ "${BIC_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

[ -r "$SRC_DIR/build-rpms.sh" ] || die "$SRC_DIR/build-rpms.sh is missing (mount rocky10.2/ at /src)"
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

rm -f "$LOG_DIR/build.ok"
build_all "$SRC_DIR/gazpacho.manifest"
collect_result
exit 0
