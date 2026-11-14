#!/usr/bin/env bash
# Run every Rocky test suite that needs no OpenStack and no network:
#   tests/test-env-file.sh            hagistack.env reader and option precedence
#   tests/test-rpm-source.sh          RPM sources, verification, guards
#   tests/test-build-in-container.sh  pass control of the source build
#   tests/test-build-rpms-staging.sh  sources re-staged before every rpmbuild
#   tests/test-build-own.sh           own packaging: our names excluded from every other repository, retries, origin checks
#   tests/test-ovs-system-id.sh       the OVN chassis name survives a restart of ovsdb-server
#   spec-adapt/test_adapt.py          spec adaptation rules and licensing
#   tests/test_release_check.py       release generator's notice and logo checks (stub rpm)
#   packaging/test_genspec.py         package definitions and spec generation
#   packaging/branding/test_branding.py  dashboard images: reproducible, shapes only
#
#   bash rocky10.2/tests/run-all.sh
#
# Run it from a full checkout: test_adapt.py's licensing tests read the
# repository-root LICENSE and READMEs, and fail (by design) on a copy of
# rocky10.2/ alone. Needs Rocky/EL 10 with rpm-build, createrepo_c, python3.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in test-env-file.sh test-rpm-source.sh test-build-in-container.sh test-build-rpms-staging.sh test-build-own.sh test-ovs-system-id.sh; do
    echo "######## $t"
    bash "$HERE/$t" || rc=1
done
echo "######## spec-adapt/test_adapt.py"
( cd "$HERE/../spec-adapt" && python3 -m unittest -v test_adapt ) || rc=1
for t in tests/test_release_check.py packaging/test_genspec.py packaging/branding/test_branding.py; do
    echo "######## $t"
    python3 -B -I "$HERE/../$t" || rc=1
done
echo
[ "$rc" -eq 0 ] && echo "ALL SUITES PASSED" || echo "AT LEAST ONE SUITE FAILED"
exit "$rc"
