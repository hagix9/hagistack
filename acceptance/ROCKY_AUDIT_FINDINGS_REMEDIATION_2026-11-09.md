# Rocky 10.2 — remediation of independent-audit findings on 2aa5b22

Branch `feat/rocky-rpm-sources-and-roles`, base `2aa5b22`. Implementer's
remediation and self-check; **not an independent audit**. The 2026-11-09
acceptance record ([ROCKY_INSTALLER_COMPLETION_ACCEPTANCE_2026-11-09.md](ROCKY_INSTALLER_COMPLETION_ACCEPTANCE_2026-11-09.md))
is unchanged.

## Findings and fixes

| ID | Cause | Fix |
|---|---|---|
| B-1 | `build-in-container.sh` judged passes by grepping results that might not exist; a missing/empty/partial results file read as "no failures"; any failure was retried | Pass control moved into functions (`expected_packages`, `check_results`, `retryable_failures`, `build_all`, `collect_result`). Exit status taken explicitly; STOP never retried; results must exist, be non-empty, well-formed and name every expected package exactly once; exit status and results must agree; only build-dependency failures (exit 11 + "is needed by") reach pass 2; pass 2 must build all of them; SRPM count must equal package count; `logs/build.ok` written last and required by hagistack |
| B-2 | Remote compute only warned when a `[database]`/`[api_database]` connection stayed active, then started nova-compute | `connection` and `slave_connection` commented out in both groups; `compute_assert_no_db` then requires none to be active in `nova.conf` **and** none in nova-compute's effective oslo.config configuration (as the nova user); otherwise, or if the check cannot run, the run stops before nova-compute is started or restarted |
| B-3 | A missing controller RPM-set identity only produced a warning | `controller_rpm_set_check`: identity required for a new remote compute node, must be 64 hex or `repo-url`, checked in `phase_secrets` (before download/install) and in the guard. Exception limited to re-runs of hosts recorded as `ROLE=compute` with a recorded set, which stay bound to that set |
| N-1 | `--build-image` did not change the build-cache identity | Image content digest included in the build input id; tag-only refs refused; pulled image must carry the pinned digest; old work directories kept, not matched |

The spec-adapt "61/61 PASS" vs "FAILED (failures=2, errors=3)" discrepancy was a
test-environment difference, not a code defect: the failing run had only
`rocky10.2/` copied (the five LicensingTests read root `LICENSE`/`README*`),
and the passing run's saved excerpt omitted the `Ran 61` line. Both cases were
reproduced on a clean `git archive 2aa5b22` tree; `tests/run-all.sh` now
documents that the suite needs a full checkout.

## Verification (2026-11-09, local Rocky 10.2 aarch64 VM; no GCE)

| Check | Result |
|---|---|
| `tests/test-rpm-source.sh` | 93 passed, 0 failed (56 pre-existing incl. 2 fixtures updated to valid 64-hex identities, +37 new) |
| `tests/test-build-in-container.sh` (new) | 37 passed, 0 failed |
| `spec-adapt/test_adapt.py` (full tree) | Ran 61, OK |
| B-1 replay of the real 2026-11-09 build results through the new functions | 69 expected, pass-1 valid, retry = neutron nova horizon, pass-2 valid, 0 FAIL — same decision as the accepted build |
| B-2 against real Nova 33.0.2 (RPMs from the 2026-11-09 set, noarch) | shipped config: no keys; comment text: passes; connection in `nova-compute.conf`, `nova.conf.d`, `slave_connection`: detected and stops; normal path: comments out, then starts; connection elsewhere: never starts |
| N-1 digest check with real podman 5.8.2 and the pinned image | pinned digest found in RepoDigests; other digest not matched |
| `bash -n` (9 scripts) | OK |
| ShellCheck 0.10.0 `-S warning` | hagistack 9 (identical to `8225c50`), all other scripts 0 |
| `git diff --check` | clean |

GCE acceptance was not repeated: the changes add stop conditions on abnormal
inputs; the normal two-pass build decision, the clean compute path and the
cache reuse were re-checked against real artifacts above. The two normal-path
additions that a GCE run would exercise for the first time are the oslo.config
check on a real x86_64 compute node and the `build.ok`/digest checks in a real
full build.
