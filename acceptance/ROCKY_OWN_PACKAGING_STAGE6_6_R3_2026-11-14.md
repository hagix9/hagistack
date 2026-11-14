# Rocky 10.2 own packaging — Stage 6-6-R3: simpler approval, GCE gate ready

Date: 2026-11-14. Branch `feat/rocky-own-packaging-s65r1`, from `b02c53b` (stage 6-6 record).

## Goal

Return to the purpose of stage 6-6: build the RPMs on Rocky Linux 10.2 x86_64 and
complete the release, nodocs, brand and all-in-one checks on GCE. The signed
approval (Owner key, pin, `.sig`) is no longer required for development runs. No
Touch ID, Secure Enclave or new authentication service was built.

## Start state (checked)

- HEAD `b02c53bf6ea17dc60bad7804f0aed7e926677ac6`, branch as above.
- The 4 stage 6-6 commits are present.
- 21 untracked entries; `rocky10.2/packaging/__pycache__/genspec.cpython-313.pyc` dated Nov 13 15:36.
- `ba3395c` unchanged.
- No difference from the expected state.

## Change

| Commit | Content |
|---|---|
| `1236c1a` | format-4 development run record; `hs6_approve.py --show` and `--dev-record`; README "Development runs"; ledger header `approval_format`; `GitObjects.close` closes its pipes |
| `986c3d0` | audit LOWs: the conditions SHA-256 also covers the validity; comments name the signed format; test for a `.sig` beside the record |

**Flow:**
1. The agent runs `hs6_approve.py --show`. It prints every condition of the run and
   one conditions SHA-256, and writes nothing.
2. The Owner approves exactly those conditions in chat.
3. The agent runs `--dev-record` with that SHA-256 and the approval note.
4. `--dev-record` recomputes the conditions and refuses, writing nothing, if they differ.
   Otherwise it writes `~/hagistack-approvals/<rid>.json` (mode 600, never overwritten).
5. `hs6.py` accepts format 4 only with:
   - the exact authority text;
   - a 1–2000 character approval note;
   - an integer `format`;
   - no `.sig` beside it.

**Checks kept for format 4, unchanged:**
- run id, project, zone and account;
- commit/HEAD binding and the harness SHA-256;
- operations, which must include `teardown`;
- budget ≤ US$8, hours ≤ 6, validity ≤ 24 h;
- one run per record and per run id;
- the run plan: only its ssh steps, only the commit's tree as upload, only its downloads and nodes;
- the cost and time guards and the test-hook refusals.

`teardown` and `residual` work after expiry.

**Not claimed:** the harness cannot tell whether the Owner approved. Any process of
the same OS user can write a format-4 record, and the same user's gcloud credentials
reach GCE without the harness. The README states the operating rule: no GCE operation
and no `--dev-record` without the Owner's explicit approval of the shown conditions.
The signed format 3 is kept but not required; `OWNER_SIGNING_KEYS` stays empty.

## Verification

| Check | Result | Category |
|---|---|---|
| Full suite at `1236c1a` (207 existing + 11 new) | 218/218 OK on 3.13 and on 3.9.6 | tests run |
| 3.9 run with per-test timing at `1236c1a` | 218/218 OK; slowest test 28 s | tests run |
| Affected classes after the LOW fixes (`986c3d0`) | 44/44 OK on 3.13 and 3.9 | tests run |
| Full suite at `986c3d0` | 218/218 OK on 3.13 (738 s) and on 3.9.6 (1513 s) | tests run |
| `--show` on the real checkout (local `gcloud config get-value account` only) | conditions printed, nothing written | real files |
| Independent audit of `1236c1a` | GO: 0 BLOCKER / HIGH / MEDIUM; 3 LOW fixed in `986c3d0`; 1 NOT VERIFIED (`--show` as a subprocess was checked by reading only; it was run by the implementer) | audit report (the auditor ran 86 tests on each version) |

**Intermittent 3.9 error (unresolved).** At the start of this stage, one full 3.9 run
reported `FAILED (errors=1)`. The log kept only its last lines, so the test is not
known. It happened while another project's test suites loaded the machine; that run
took 2110 s against about 1230 s for the same suite later. Since then, five full 3.9
runs passed, including one with per-test timing whose slowest test took 28 s. The
same kind of single unexplained 3.9 failure was seen once in stage 6-6. The most
likely cause is a wall-clock limit in the tests (subprocess timeouts of 60–120 s,
`assertLess(..., 25)`) under CPU contention, but this is not proven. It is recorded
as unresolved, not as a pass. It does not touch the GCE run: the tests use mocks only.

## GCE gate

The run conditions come from `hs6_approve.py --show --run-id <rid>` at the final
commit. They are shown to the Owner, and nothing runs until the Owner approves them.
- Node: n1, n2-standard-8, pd-standard 100 GB.
- Image: `rocky-linux-cloud/rocky-linux-10`; the node checks for Rocky 10.2 x86_64.
- Zone: asia-northeast1-a.
- Limits: 6 h and US$8 (list-price estimate: about US$2.6 at 4 h, US$3.6 at 6 h).
- The run's own VPC, subnet, firewall, router and NAT are deleted at the end.
- No push, merge, tag or Release.

The run plan SHA-256 is unchanged from stage 6-6
(`58459f5233a79a67f5ee554a07e3e53b9a0211cedfccb612fe4e3ed3619ee429`). The tree SHA-256
changes with every commit, because the archive carries the commit's time.

Verdict at the end of this preparation: **OWNER APPROVAL WAIT**.

## GCE run s66r3a (after the Owner's approval)

The Owner replied `s66r3a 03a302e8 承認` in chat to the conditions `--show` printed at
`b3d3589`. The record was written with `--dev-record`; its conditions SHA-256 matched
(`03a302e8…`). Times below are in UTC on 2026-11-14.

| # | Step | Result |
|---|---|---|
| 1 | init (quota, image, baseline) | passed. 96 existing resources recorded; image `rocky-linux-10-v20261110` |
| 2 | network and n1 (n2-standard-8, pd-standard 100 GB) | created |
| — | tree upload and extract | SHA-256 `b183ce3a…` verified locally and by the node |
| — | preflight | 0 failed checks. Rocky Linux 10.2, x86_64, vmx, SELinux enforcing |
| 3 | build | **passed** in 5804 s: 69 SRPMs, 195 RPMs. Set `4ee923b64a1029d02b93ce36e42f187008c2be36fa0960a75bb17167959ee675` is new (not `6c43da…`). Every RPM's source RPM is in the set |
| 4–5 | release | **failed** (see below) |
| 6–11 | nodocs, pack, downloads of candidate and build evidence, install, all-in-one, acceptance | not run. The node script refuses a step whose previous step did not pass |
| 12 | evidence | passed. `evidence-final.tar` (398 entries) downloaded; SHA-256 `8075bce5…` matched the node's |
| 13 | teardown | n1, nat, router, both firewall rules, subnet and network deleted |
| 14 | residual | "none of run s66r3a left"; `watch` reported the run torn down |

The harness's cost estimate was US$1.39 accrued (US$0.54 of it assumed for egress and
NAT data). The run took 1.72 h from the first creation. This is an estimate; the bill
is in Cloud Billing.

**The release failure.** `make-rpm-release.sh` passed the set, header, licence-file,
manifest and source-RPM checks. It then stopped at the change-notice check:

> `python3-keystone+ldap-29.1.0-2.el10.noarch.rpm` must install HAGISTACK-CHANGES …; it installs none

Cause: the generator and the checker disagree.
- `genspec.py` (`carries_changes`) leaves `kind = "extras"` subpackages out of
  `HAGISTACK-CHANGES`.
- An extras subpackage comes from `%pyproject_extras_subpkg` and has no `%files` of
  its own in the generated spec. It only carries the requirements of the extra, so
  it ships no file at all.
- `release_check.py check_notices` demands the notice from every binary RPM of a
  source RPM that declares changes.

Nine extras subpackages exist (keystone, glance-store, oslo-cache, oslo-db,
oslo-service, tooz). The check stops at the first one whose source RPM has changes.
This check was added in stage 6-5-R2 and had not run on real RPMs before this run.

The RPMs themselves are not shown faulty by this: what fails is the rule in the
checker. The fix is a change to `release_check.py` (or to `genspec.py`) plus a local
test, then a new GCE run under a new run id. That needs a new approval from the
Owner.

Evidence: `<TMP>/hagistack-s66r3a/state/` on the external SSD. It holds the ledger,
`operations.log`, the remote logs, step outputs and `downloads/evidence-final.tar`.

Verdict: **NO-GO**. The RPM build passed on real hardware. The release check failed
on a checker/generator mismatch, so nodocs, brand, all-in-one and acceptance were not
reached. No GCE resource of the run is left.
