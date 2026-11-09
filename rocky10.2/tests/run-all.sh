#!/usr/bin/env bash
# Run every Rocky test suite that needs no OpenStack and no network:
#   tests/test-rpm-source.sh          RPM sources, verification, guards
#   tests/test-build-in-container.sh  pass control of the source build
#   spec-adapt/test_adapt.py          spec adaptation rules and licensing
#
#   bash rocky10.2/tests/run-all.sh
#
# Run it from a full checkout: test_adapt.py's licensing tests read the
# repository-root LICENSE and READMEs, and fail (by design) on a copy of
# rocky10.2/ alone. Needs Rocky/EL 10 with rpm-build, createrepo_c, python3.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in test-rpm-source.sh test-build-in-container.sh; do
    echo "######## $t"
    bash "$HERE/$t" || rc=1
done
echo "######## spec-adapt/test_adapt.py"
( cd "$HERE/../spec-adapt" && python3 -m unittest -v test_adapt ) || rc=1
echo
[ "$rc" -eq 0 ] && echo "ALL SUITES PASSED" || echo "AT LEAST ONE SUITE FAILED"
exit "$rc"
