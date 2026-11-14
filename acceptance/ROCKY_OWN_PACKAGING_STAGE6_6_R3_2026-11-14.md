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

## Fixes after run s66r3a

| Commit | Content |
|---|---|
| `669b8bf` | `release_check.py check_notices` skips a binary RPM whose payload has no regular file (an extras subpackage). It does not count as a binary of its source, so a changed source with only such binaries is still refused. Two tests were added |
| `0a78dc6` | Audit H-1: `s66-node.sh s_nodocs` compared the marked files of the `--excludedocs` root and of the root with docs. Placement's marked `policy.yaml.sample` is installed as `%doc`, so it is absent from the first root by design, and the comparison would have failed on the next run. Now `usr/share/doc/` of the root with docs is left out of the comparison and recorded in `marked-doc-files.txt`. L-1: the release check's docstring, `make-rpm-release.sh` and `THIRD_PARTY_NOTICES.md` name the extras exception |
| this commit | LOW-3: one more sentence of `THIRD_PARTY_NOTICES.md`; this section |

**Verification.**
- `tests/test_release_check.py`: 24 tests OK on 3.13; 24 OK on 3.9 (1 skipped, genspec needs 3.11+).
- `test_s66_node` and `test_s66_web`: 31 tests OK on 3.13 and on 3.9.
- `packaging/test_genspec.py`: 38 tests OK on 3.13.
- The new mark comparison was run in a shell on sample roots: 4 cases by the implementer, 7 by the auditor.

**Independent audit.**
- `669b8bf`: NO-GO, only because of H-1 (outside that commit).
- `669b8bf` + `0a78dc6`: GO. 0 BLOCKER / HIGH / MEDIUM.
- LOW-1: there is no automated test of the `s_nodocs` comparison; the sample-root runs are the evidence.
- LOW-2: `marked-doc-files.txt` is recorded but not checked.
- LOW-3 is fixed here.

**Still not verified (NV-1).** On real RPMs, nothing after RPM number 112 of the notices check has run yet: the remaining 84 RPMs, the marks match, branding, members and lock generation. Only a new run shows them.

A new run needs a new run id and the Owner's approval of the conditions that `--show` prints at the final commit.

## GCE run s66r3b (after the Owner's approval)

The Owner replied `s66r3b 67923078 承認` to the conditions `--show` printed at
`38053ad`. The record was written with `--dev-record` and the conditions SHA-256
matched.

| # | Step | Result |
|---|---|---|
| 1–2 | init, network, n1 | passed. Image `rocky-linux-10-v20261110` |
| — | upload, extract, preflight | passed. Tree `960a1ac5…` verified; Rocky Linux 10.2 x86_64, vmx, SELinux enforcing |
| 3 | build | **passed** in 5772 s: 69 SRPMs, 195 RPMs. Set new, not `6c43da…` |
| 4–5 | release | **passed**. make-rpm-release.sh twice, byte-identical candidates, lock names the set, 195 RPMs and tag `rocky10.2-rpms-2026.1-rc3`, SHA256SUMS verify. The change-notice check passed for every RPM with files |
| 6 | nodocs | **passed**. 170 RPMs carry a notice; all kept under `--excludedocs`; no file under /usr/share/doc (6016 with docs); HAGISTACK-LICENSE 170 of 170; 34 marked files the same in both roots (plus 1 marked documentation file only with docs) |
| 9 | pack and downloads | passed. `candidate.tar` `b4ee5275…` and `evidence-build.tar` `780b635d…`, SHA-256 matched the node's |
| 10 | all-in-one install | **passed** in 496 s. The deployment records the new set, not the old one; 104 installed packages carry the set's headers; no novnc |
| 11 | acceptance | **7 failed checks** (below) |
| 12 | evidence | passed. `evidence-final.tar` `7008af9e…` downloaded and matched; the secret scan found nothing |
| 13–14 | teardown, residual | n1 and the network deleted; "none of run s66r3b left" |

The harness's cost estimate was US$1.65 accrued over 2.22 h.

**Acceptance. These passed before and after the restart of 14 units:**
- Keystone token, Nova API and services, Neutron API, Placement, hypervisor up;
- the Horizon sign-in test (`tests-horizon-login.sh`);
- Hagistack's favicon, apple-touch-icon, safari-pinned-tab, logo and logo-splash on
  the login and admin pages;
- the documentation RPM installs, and all its theme logos and favicon are Hagistack's.

Also passed: guest s66-g1 SSH and metadata before the restart, 0 failed units, and
only the new set's packages installed.

**The 7 failures:**

| Check | Failure | What the evidence shows |
|---|---|---|
| Horizon pages, before and after the restart (2) | `static/bootstrap/fonts/bootstrap/glyphicons-halflings-regular.{eot,woff2,woff,ttf,svg}` return HTTP 404 | The fonts belong to `python3-XStatic-Bootstrap-SCSS` / `xstatic-bootstrap-scss-common` 3.3.7.1-14.el10s, which is not part of the Hagistack set. Whether that package leaves them out, or Horizon's static files point to the wrong place, is not determined. Every Hagistack image loaded |
| documentation page (1) | `_static/images/side-note-pointer.gif` returns HTTP 404 | The theme's stylesheet refers to an image that is not installed. Whether upstream ships it is not determined. Every Hagistack logo loaded |
| s66-g1 pings s66-g2, before the restart (1) | 0 of 5 received | The ping runs once, right after s66-g2 becomes ACTIVE, with no wait for its boot. The SSH check, by contrast, waits up to 300 s. The security group allows ICMP. Cause not determined: a guest that has not finished booting, or a real data-path fault |
| Neutron agents alive, after the restart (1) | not all alive within 300 s | Not determined. The evidence has no agent list, no unit journals and no OVN state |
| s66-g3 SSH and metadata, after the restart (2) | no SSH; empty instance-id | Consistent with the metadata agent not working after the restart (the key comes from metadata), but not determined, for the same reason |

**Evidence gap.** `s66-node.sh` keeps the step logs, but not:
- `openstack network agent list`;
- the journals of the Neutron, OVN and Nova units;
- `ovn-sbctl show`;
- the guests' console logs.

So the network failures cannot be diagnosed from this run.

Verdict: **NO-GO**.
- Build, release, nodocs, the RPM set, the change notices, the all-in-one install,
  the core APIs and Hagistack's branding are verified on real hardware.
- Tenant connectivity (guest-to-guest ping) and Neutron after a restart (agents,
  metadata) failed.
- Two pages load assets that return 404.

The next run would need:
- a diagnosis of the network failures;
- more evidence captured (the list above);
- a wait before the ping;
- a decision on the two 404s (fix them, or exclude assets that are not Hagistack's,
  with a reason).

Each further run needs a new approval.

## Preparation for the next run (after s66r3b)

| Commit | Content |
|---|---|
| `09e1ed3` | Changes to `s_accept` and `s_evidence` (listed below), the script header, and tests |
| this and the previous commit | audit LOWs: the newest 3000 journal lines with their exit status; 404 file names without a query string; diag directories 0700; a NOTE on whether the first ping was answered |

`09e1ed3` changes:
- `s_accept` gives the second guest up to 300 s for a first ping reply before it counts 5.
- `diag` keeps, before and after the restart and again in evidence:
  - the agent, service, server, port and security-group lists;
  - `ovn-nbctl show`, `ovn-sbctl show` and `ovs-vsctl show`;
  - the network namespaces and addresses;
  - `systemctl status` of 11 units;
  - the guests' console logs and journal tails.

  Every command is bounded.
- `asset_diag` records where each asset that returned HTTP 404 is installed, if anywhere, and by which RPM.
- `s_evidence` withholds every diagnostic file in which a secret value appears and lists its name. The final full scan still stops packing on any hit.

The two 404 checks are unchanged: they still fail if the assets are missing.

**Verification.** `test_s66_node` and `test_s66_web` pass, 44/44 on 3.13 and on 3.9. A new test runs the real `s_evidence` on a copy and checks that a diagnostic file holding a private key is withheld and the rest packed.

**Independent audit of `09e1ed3`:** GO, with 0 BLOCKER / HIGH / MEDIUM.
- LOW-1, LOW-2, LOW-5 and part of LOW-4 are fixed.
- Still open:
  - LOW-3: `asset_diag` is not bounded by the number of URLs;
  - LOW-4: the agent list is not kept at the moment of the failure;
  - LOW-6: there are no runtime tests of `diag`.
- NOT VERIFIED: that cirros's ping accepts `-W 2`. If it does not, the check waits 300 s and then counts, so it cannot pass falsely.

**Still open: the two 404s.** They come from assets that are not in the Hagistack set:
- the glyphicons fonts of `xstatic-bootstrap-scss-common` (el10s);
- the documentation theme's `side-note-pointer.gif`.

Whether to keep them as failures, or to exclude assets that no Hagistack RPM ships, with a reason, is the Owner's decision. The next run records where those files are, if anywhere.
