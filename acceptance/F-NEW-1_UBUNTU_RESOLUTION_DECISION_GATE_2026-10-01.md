# F-NEW-1 on Ubuntu 26.04: resolution decision gate

Read-only research, 2026-09-30 22:49Z – 2026-10-01 (queries stamped in the evidence files). **Untracked and
unstaged by design.** Nothing was implemented, built, submitted, filed or pushed.

Raw evidence (103 files, `SHA256SUMS` SHA-256 `85ed11ac7de5744f9f6e2670d1abe2fcc3d9ce2f76ea6765765e4d72c14fd567`):
`/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-ubuntu-decision-gate-2026-10-01/evidence/`.
The disposable Neutron clone with the local rebased branches is `…/neutron/` in the same directory.

Tags used: **[OBSERVED]** seen in a live source today; **[SOURCE]** verified from source code; **[INFERENCE]** my reading;
**[EXTERNAL]** depends on a process outside Hagistack's control.

---

## Conclusions

1. Nothing has changed in Ubuntu's favour since the last reassessment. The Ubuntu 26.04 package is still
   `2:28.0.2-0ubuntu1`, byte-identical in the relevant files to upstream 28.0.2, with no pending upload, no
   Launchpad bug, no SRU. **[OBSERVED]**
2. stable/2026.1 still lacks the fix (head moved to `29d4ee42e2`; the new commit is an unrelated DNS maintenance task). No
   stable review, no Launchpad series task, no release request exists. **[OBSERVED]**
3. The prepared two-change backport remains correct on the current head: it applies cleanly, is semantically the
   master pair, and passes 1052 targeted unit tests and the lock-request matrix on the current head. **[SOURCE]**
4. There is a concrete, supported Ubuntu path (stable backport → next Neutron 28.0.x point release → Ubuntu point-release
   SRU, or a direct Ubuntu cherry-pick SRU), but every step needs an external party. **[EXTERNAL]**
5. No supported Ubuntu stream that already contains the fix exists for Hagistack's 26.04/2026.1 target. The fix
   exists in the Ubuntu development series (26.10) and in UCA `hibiscus-proposed` (a different OpenStack release).
6. **Decision: DECISION READY.** The model is preservable only after external action; nothing Hagistack-private is
   needed or recommended.

---

## 1. Repository preflight

| | |
|---|---|
| branch / HEAD | `fix/rocky-neutron-maintenance-lock` / `dd752d42840ae8c7e792bfcc6af4b52bc65f7a8d` (as expected) |
| `git diff`, `git diff --cached` | both empty; no tracked product change (`git diff --name-only 40472e8 HEAD` outside `acceptance/`: 0) |
| untracked | `AGENTS.md` (symlink), `…UBUNTU_RESOLUTION_REASSESSMENT…`, `…NEUTRON_STABLE_2026_1_BACKPORT_PREPARATION…`, this report |
| Rocky | `dd752d4`, `2077950`, `40472e8` present; nine F-NEW-1 Rocky/investigation reports committed in `dd752d4` |
| input report hashes at start | reassessment `e6f7125d…b2`, preparation `613a911e…7c` (not modified) |

`git log`: `dd752d4 → 2077950 → 40472e8 → 2556d83 → cb3154a → 7a20dbe (origin/master)`.

## 2. Input report assessment

### 2.1 Reassessment (`…UBUNTU_RESOLUTION_REASSESSMENT_2026-10-01.md`)

| Claim | Status | Basis today |
|---|---|---|
| Ubuntu 26.04 Neutron = `2:28.0.2-0ubuntu1`, resolute-updates 2026-09-24; nothing newer in proposed or queues | **VERIFIED** | Launchpad `getPublishedSources` and `getPackageUploads`, 2026-09-30T22:50Z |
| Ubuntu source = upstream 28.0.2 in all maintenance/OVSDB files; Ubuntu's 3 patches touch other files | **VERIFIED** | `.dsc` SHA-256 `1fe00fb8…85ce` unchanged; `maintenance.py`, `impl_idl_ovn.py`, `mech_driver.py`, `constants.py`, `worker.py`, `service.py` hashes equal tag 28.0.2; patches touch `MANIFEST.in`, `wsgi_utils.py` and two tests |
| stable/2026.1 lacks the three commits; no Gerrit change | **VERIFIED**; the quoted base `8c1075228f` is **STALE** | head is now `29d4ee42e2` |
| Pair applies cleanly to stable/2026.1; `91abb5e7` alone and `c695003d` conflict | **VERIFIED** on the current head | §7 |
| LP #2155155/#2156979: one `neutron` task each, no stable/Ubuntu task, last activity 2026-07-16 | **VERIFIED** | §8 |
| No Ubuntu bug matches the lock terms | **VERIFIED** | searched since 2026-06-01 incl. `cloud-archive` and `neutron` projects |
| Stonking's Neutron 29.0.0~rc1 contains the fix (was "inference from the tag") | **VERIFIED** (now from source) | preparation report §Q; archive record re-queried today, still Published |
| "UCA hibiscus-staging holds 29.0.0~rc1 for resolute" | **PARTIAL / STALE** | now also in `hibiscus-proposed`; `hibiscus-updates` has no Neutron; `gazpacho-updates` Neutron is for **noble**, not resolute |
| Dependencies unchanged (python3-openvswitch 3.7.1-2, ovsdbapp 2.16.0-2) and do not remove the race | **VERIFIED** for resolute; stonking's newer ovsdbapp 2.19.0 not inspected (irrelevant to 26.04) | archive + prior source reading |
| SRU policy prefers point releases; cherry-picks for high-impact/obviously safe | **VERIFIED** | §12 |
| 28.0.2: tag 2026-09-10 → updates 2026-09-24 (~2 weeks) | **VERIFIED** | tag commit 2026-09-10T21:05Z, annotated tag 2026-09-11, proposed 09-16, updates 09-24 |
| Decision "WAIT FOR OFFICIAL PACKAGE: NO EVIDENCE OF PROGRESS", custom package not required | **VERIFIED** as of today | no Gerrit/LP/Ubuntu activity found |

### 2.2 Preparation (`…NEUTRON_STABLE_2026_1_BACKPORT_PREPARATION_2026-10-01.md`)

| Claim | Status | Basis today |
|---|---|---|
| Identities/Change-Ids/bugs of `83f1d830`, `91abb5e7` | **VERIFIED** | fresh clone; no follow-up fix to the pair on master or stable/2026.2 (only those two commits touch `set_lock`/`lock_name`) |
| Base = stable/2026.1 `8c1075228f` | **STALE** | now `29d4ee42e2` (+2 commits: an unrelated DNS maintenance task and its merge) |
| Both local commits are exact cherry-picks; semantic delta zero | **VERIFIED** on current head | merge-tree tree `262b53ea…` = rebased series tree; changed lines identical to the master commits |
| Change 1 alone is unsafe (RPC worker, sync-util/upgrade-check callers, RPC-first ordering) | **VERIFIED** | current-head tree shows `idl_.set_lock(ovn_const.…)` in the shared branch; harness (§7.4) |
| Final series: maintenance worker requests the lock, RPC worker does not | **VERIFIED** | §7.4 |
| Deterministic regression PASS (10/10 → 0/10) | **VERIFIED** on the current head (5/5 → 0/5) **with the stub-peer limitation** | §7.4; stub is not `ovsdb-server` |
| Targeted unit set 1049 tests, 0 failed | **PARTIAL (old base)**; on current head **1052 tests, 0 failed** (base, Change 1 only, series) | §7.4 |
| Full-suite: 3 platform failures + flaky `TestNovaSegmentNotifier` on base | **not re-run**; accepted as OBSERVED on the old base | — |
| Stable policy eligibility YES | **VERIFIED** | §7.5 |
| stable/2025.2 and 2025.1 carry the same defect | **VERIFIED** | both: `set_lock` in `DBInconsistenciesPeriodics.__init__` and `RpcWorker` in the shared `from_worker` branch |
| Gerrit/Zuul enforcement of "pair must merge together" not verified | **PARTIAL** (still unverified, correctly disclosed) | — |
| No external lock waiter in the validation | **VERIFIED** | scripts contain no `ovsdb-client` and no `lock`/`steal` request from the test side; the only waiters are the stub's own queueing and the two real workers in the handover scenario |
| Verdict "SUBMIT READY / DO NOT SUBMIT" | **VERIFIED** with pre-push housekeeping (§10) | — |

No claim was found **CONTRADICTED** or **UNSUPPORTED**.

## 3. Current upstream stable/2026.1 state [OBSERVED]

Fresh clone of `https://opendev.org/openstack/neutron`, 2026-09-30T22:49:06Z–22:49:58Z.

| | |
|---|---|
| stable/2026.1 HEAD | `29d4ee42e2e7601b7116a27300d7e035464bc868` (2026-09-30T22:39:46Z, `28.0.2-20`) |
| master HEAD | `97f4dadd06a08a478cc702bc55353d2da59ca267` (2026-09-30) |
| stable/2026.2 HEAD | `7121bf42621e8f2860100b3bb0e7e9089c007959` (`29.0.0-5`) |
| newest release tag on the 28.x line | `28.0.2` (2026-09-10/11); no 28.0.3 tag |
| commits on stable/2026.1 since last research (`8c1075228f`) | `43a7cea046` "Add ovn maintenance task to clean dns entries" (Closes-bug #2168032) and its merge; it adds one `@has_lock_periodic` task in `maintenance.py` and does not touch any lock-related line |
| release status | 2026.1 "Maintained" (unmaintained date estimated 2027-10-27) [fetched 2026-09-30] |

## 4. Status of the three upstream commits [OBSERVED / SOURCE]

| Commit | Change-Id | master | stable/2026.2 | stable/2026.1 | Gerrit |
|---|---|---|---|---|---|
| `c695003d1012…` | `I80e74a39…` | merged | merged | **absent** (SHA, Change-Id, bug: 0 hits; not an ancestor) | 991346 master MERGED; no other change |
| `83f1d8305651…` | `Iaefe1e2c…` | merged | merged | **absent** | 992569 master MERGED; no other change |
| `91abb5e720e1…` | `I74145ef1…` | merged | merged | **absent** | 993860 master MERGED; no other change |

Source check, not message search: stable/2026.1 `maintenance.py` still contains `self._idl.set_lock(MAINTENANCE_NB_IDL_LOCK_NAME)`
and `has_lock` = `not self._idl.is_lock_contended`; `impl_idl_ovn.py` has no `set_lock`/`lock_name`; `mech_driver.py` has no
`lock_name`. stable/2026.2 and master: `from_worker` ends with `idl_.set_lock(worker_class.lock_name)` under
`except AttributeError`, and `post_fork_initialize` sets `worker_class.lock_name`. The minimal causal pair is still
`83f1d830` + `91abb5e7`; `c695003d` is still not required (no evidence to the contrary).

## 5. Stable backport status [OBSERVED]

- No Gerrit change on `stable/2026.1` for bug 2155155 or 2156979 (any status), none whose message mentions
  `MaintenanceWorker`, `set_lock` or "maintenance worker lock". Open stable/2026.1 changes today are four unrelated ones
  (1007629, 1006082, 1002462, 1007630); the four abandoned ones are CI tests and unrelated.
- No stable backport is proposed, merged, abandoned or superseded.
- `openstack/releases`: no open change for Neutron; last Gazpacho release change 1004929 (28.0.2, merged 2026-09-11).
  Cadence of the 28.x tags: 2026-04-01, 2026-07-01, 2026-09-11. **[INFERENCE]** a further 28.0.x is plausible within months, but no
  date or request exists, and none is asserted here.
- Stable policy still permits it: bug fix, already on master and stable/2026.2, 2026.1 Maintained.

## 6. Ubuntu 26.04 package state [OBSERVED]

Launchpad, Ubuntu primary archive, series resolute (Current Stable Release), queried 2026-09-30T22:50:58Z:

| Package | Release | Updates | Proposed | Security/Backports |
|---|---|---|---|---|
| neutron | `2:28.0.0-0ubuntu1` (2026-04-07) | **`2:28.0.2-0ubuntu1`** (2026-09-24; previous `2:28.0.0-0ubuntu1.1`, superseded) | only the same 28.0.2 upload (2026-09-16) | none |
| python-ovsdbapp | 2.16.0-2 | none | none | none |
| openvswitch (python3-openvswitch) | 3.7.1-2 | none | none | none |
| python-neutron-lib | 3.24.0-2 | none | none | none |

Upload queues for `neutron` in resolute (New, Unapproved, Accepted, Rejected): empty. **No newer package has appeared.**

Source: `.dsc` `1fe00fb84f2c1da6c1f8057eac9f17b2c6626cd1ea7c8320c07403831ee685ce`, orig `cdaf45a2…25ee` (equal to upstream 28.0.2), debian
`bb1434e7…8585`. Source basis: upstream tag `28.0.2` (resolute gbp branch `stable/2026.1`).

Other series/streams (context for U6):
- stonking (26.10, Pre-release Freeze): `neutron 2:29.0.0~rc1-0ubuntu1` (Release, 2026-09-16), `python-ovsdbapp 2.19.0`, `python-neutron-lib 5.0.1`, openvswitch 4.0.0-1 in proposed.
- UCA: `gazpacho-updates` Neutron `2:28.0.2-0ubuntu1~cloud0` is for **noble**; `hibiscus-proposed` Neutron `2:29.0.0~rc1-0ubuntu1~cloud0` for **resolute**; `hibiscus-updates` has no Neutron.

## 7. Ubuntu delta and backport correctness

### 7.1 Ubuntu delta [SOURCE]

`debian/patches/series`: `install-missing-files.patch` (MANIFEST.in), `skip-iptest.patch` (a unit test),
`lp2150285-keep-mod-wsgi-operational.patch` (`neutron/common/wsgi_utils.py` + its test). None touches the maintenance worker,
`impl_idl_ovn.py`, `mech_driver.py`, `constants.py`. No equivalent fix under another identity; the changelog of the last
three uploads mentions no lock change.

### 7.2 The pair applies to Ubuntu's basis [SOURCE]

`83f1d830` then `91abb5e7` on tag `28.0.2` (the Ubuntu orig) merge cleanly to a 4-file, +8/−3 result whose changed lines
are identical to the result on the current stable/2026.1 head. 28.0.2 also has `n_service.RpcWorker` in the shared
`from_worker` branch, so Change 1 alone is unsafe for Ubuntu too.

### 7.3 Backport onto the CURRENT stable/2026.1 [SOURCE]

- `git merge-tree --write-tree` (no cherry-pick command in the Hagistack repository; in the disposable clone I also cherry-picked to get worktrees): Change 1 clean; Change 2 clean on top
  (tree `262b53ea7ad6cb5cf3dd0ff7ec67f0d951a4da51` = tree of the rebased branch `dg-series` `5e01a44fd2…` over `39af200c41…`).
- `91abb5e7` alone on the current head: conflict in `impl_idl_ovn.py`. `c695003d`: conflict in `neutron/services/bgp/reconciler.py`.
- The branch diverged from the prepared base only by the DNS task (maintenance.py lines elsewhere, plus its test).
- Source meaning: the final `from_worker` body equals stable/2026.2's; `post_fork_initialize` sets `MaintenanceWorker.lock_name`;
  `RpcWorker` has no `lock_name`; `maintenance.py` has no `set_lock`; `has_lock` still reads `is_lock_contended` (`c695003d` optional).

### 7.4 Behaviour on the current head [OBSERVED]

Environment as in the preparation report (macOS, Python 3.12, python-ovs 3.7.0 and ovsdbapp 2.16.1 whose `idl.py`/`connection.py` are
byte-identical to Ubuntu's 3.7.1/2.16.0). Same harness, one interpreter per start, OVSDB protocol **stub** (not `ovsdb-server`).

| Tree (current head `29d4ee42e2`) | targeted unit tests | widened: stuck / starts | RPC worker lock requests | direct `from_worker(Maintenance)` lock requests | RPC first → maintenance worker |
|---|---|---|---|---|---|
| stable/2026.1 | 1052 run, 1049 pass, 3 skip, 0 fail | **5 / 5** (5 NOT_LOCKED) | 0 | 0 | owns lock, write OK |
| Change 1 only | 1052 / 1049 / 3 / 0 | 0 / 5 | **1** | **1** | **contended, write fails** |
| Series | 1052 / 1049 / 3 / 0 | **0 / 5** | 0 | 0 | owns lock, write OK |

Unmodified window: 0/5 stuck on all trees, one lock request per start. Raw: `evidence/unit/G-*, H-*, I-*`, `evidence/regression/`.

### 7.5 Stable policy (re-read) [OBSERVED]

project-team-guide/stable-branches: backport of a change already on master; N-1/N branches first; `cherry-pick -x`; keep the
Change-Id; two stable +2; no features/API/DB/config changes. releases.openstack.org: 2026.1 Maintained, 2026.2 Maintained.
Eligible.

## 8. Launchpad and SRU status [OBSERVED, 2026-09-30T22:52Z]

| Bug | Title | Tasks | Last activity |
|---|---|---|---|
| **#2155155** | OVN maintenance worker uses is_lock_contended instead of has_lock… | `neutron` Fix Released Medium (2026-06-10); **no 2026.1 series task; no Ubuntu task** | 2026-07-16, 7 messages |
| **#2156979** | [OVN] neutron-ovn-db-sync-util repair mode fails with OVSDB lock error after "Ensure MaintenanceWorker lock set before connect" | `neutron` Fix Released High (2026-06-18); **no series/Ubuntu task** | 2026-07-16, 6 messages |

- No Ubuntu/`cloud-archive` bug, package task, SRU proposal, upload, `-proposed` package, verification tag, rejection or
  duplicate matches this issue (text searches for `lock`, `NOT_LOCKED`, `set_lock`, `maintenance worker`,
  `ovn_db_inconsistencies`, both bug numbers, for `neutron`, `python-ovsdbapp`, `openvswitch`, `ovn`, `cloud-archive`).
- Neutron tasks created since 2026-09-01: #2156587 (haproxy metadata 502, Fix Released 2026-09-18 for devel) and #2167438 (`[SRU] Neutron gazpacho stable releases`,
  Invalid on the generic task, Fix Released for Resolute 2026-09-24).
- Related but different: **LP #2168768** (New, High, 2026-09-28) "BGP topology reconciler self-deadlocks on OVSDB lock acquisition": a
  BGP-only `notify_lock` deadlock in functional CI, not F-NEW-1 and not on 26.04.
- Relationship to the issue: #2155155 and #2156979 are the upstream records of the pair; neither states the dropped-reply symptom. **[INFERENCE]** The persistent
  `NOT_LOCKED` evidence is new information for upstream and Ubuntu.
- Precedent for how Ubuntu tracks such fixes [OBSERVED]: #2156587 carries `neutron (Ubuntu Resolute)` **Fix Committed**; the 28.0.2 changelog
  drops `d/p/fix-metadata-gzip-double-decode.patch` "fixed upstream". #2150285 (mod_wsgi) shipped as `2:28.0.0-0ubuntu1.1` with
  `d/p/lp2150285-keep-mod-wsgi-operational.patch` and `verification-done-resolute` (an Ubuntu-specific patch SRU, not an upstream cherry-pick).

## 9. Distro-package-model answer

**CAN HAGISTACK CLOSE UBUNTU F-NEW-1 TODAY WHILE PRESERVING THE NORMAL UBUNTU DISTRO-PACKAGE MODEL? CONDITIONAL**

- Not today: no consumable supported Ubuntu package for 26.04 contains the root fix (`2:28.0.2-0ubuntu1`, nothing in proposed).
- A concrete distro path exists (stable/2026.1 backport → 28.0.x point release → Ubuntu point-release SRU; or a direct Ubuntu
  cherry-pick SRU) but each step is an **[EXTERNAL]** event: stable-maintainer approval, a release request/tag, an Ubuntu upload,
  `-proposed` verification, publication to `-updates`.
- A Hagistack-private package is not counted.

`UBUNTU DISTRO-PACKAGE MODEL: PRESERVABLE AFTER EXTERNAL ACTION`

## 10. Paths U1–U6

| Path | Technically possible | Actionable now | Preserves model | External acceptance | Root fix or mitigation | Material consequences |
|---|---|---|---|---|---|---|
| **U1** wait for an upstream backport, then SRU | yes | **no**: nothing exists to wait for (no change, no task, no request found) | yes | yes (upstream, then Ubuntu) | root fix (eventually) | open-ended; "NO EVIDENCE OF PROGRESS" |
| **U2** propose the stable/2026.1 backport, then SRU | yes | **yes**: prepared and re-verified; needs a human contributor with a Gerrit/Launchpad identity | yes | yes: two stable +2; a release request; then the Ubuntu point-release SRU | root fix | Ubuntu picks it up only with a 28.0.x tag; 28.0.2 took ~13 days from tag to `-updates` (09-11 → 09-24). Release date unknown |
| **U3** Ubuntu carries the two patches as an SRU delta before an upstream merge | yes (applies to 28.0.2; fix already in the devel series) | yes in principle (prepare); upload needs Ubuntu upload rights | yes | yes: SRU team and the OpenStack team | root fix | Ubuntu OpenStack SRU text accepts point releases, high-impact bugs, or "obviously safe patch"; F-NEW-1 is silent, ~6 % of observed starts, so **acceptance is not assured** **[INFERENCE]**. Order rule: upstream first "when possible". Version shape `2:28.0.2-0ubuntu1.1` |
| **U4** Hagistack maintains a custom Ubuntu Neutron package | yes (pair applies) | technically yes | **no** | none | root fix | changes ownership, security tracking, provenance, release process; requires a project-level decision; **not recommended** |
| **U5** runtime restart/health-check mitigation | yes | yes | yes | none | **mitigation only** | covers Hagistack runs only; does not cover reboot, manual, package or crash restarts; ~6 % re-roll; new self-healing behaviour [PRIOR analysis] |
| **U6** move to a stream that already has the fix | only as below | **no** | partly | yes | root fix | stonking (26.10) is a development release, not 26.04. UCA `hibiscus-proposed` Neutron 29.0.0~rc1 for resolute is proposed-only and is a different OpenStack release (2026.2) than Hagistack's 2026.1 stack; UCA `gazpacho` is for noble. No supported, compatible stream exists today |

U2 and U3 are not exclusive: U2's upstream review is also the evidence the SRU team would want.

## 11. Stable/2026.1 backport preparation readiness

**STABLE/2026.1 BACKPORT PREPARATION: READY** (content verified on the current head).

Conventions checked: original Change-Ids retained; `(cherry picked from commit …)` present once per commit; order Change 1 → Change 2; target `stable/2026.1`;
subjects ≤ 50 characters, body ≤ 72 columns; `Related-Bug: #2155155` / `Closes-Bug: #2156979` kept; no tests added (none in the
master commits; none exists for the race); pair dependency and the reason stated in both messages; stable-policy case in
`REVIEWER_JUSTIFICATION.md`.

Pre-push housekeeping (no change to the code or the substance of the messages):
1. Let `git review`/a rebase move the pair onto the current head (`29d4ee42e2`). If re-picked with `git cherry-pick -x`, a second
   "(cherry picked from …)" line appears; use `git rebase` instead. (My test re-pick did produce the duplicate line; not used as the reference.)
2. Re-commit under the real submitter's identity (the local committer is a placeholder).
3. Decide the merge guard: Gerrit cannot merge Change 2 before Change 1, but Change 1 could merge alone; enforcement by
   Gerrit/Zuul was **not verified**. Use the commit-message warning, a first review comment, and optionally Workflow −1 on
   Change 1 until Change 2 has its votes, or squash the pair into one change if the stable maintainers prefer.
4. Add 2026.1 series tasks to #2155155/#2156979 (a person with bug rights).
5. The preparation's regression ran against a protocol stub, not `ovsdb-server`. Not needed for upstream review, but a real-server
   re-run (Linux host) would strengthen the SRU case. It needs infrastructure authorisation that this task does not have.

`STABLE/2026.1 BACKPORT: READY TO SUBMIT`

## 12. Ubuntu SRU readiness

Policy sources (fetched 2026-09-30/10-01): Ubuntu "Stable Release Updates for OpenStack and the UCA"
(`https://ubuntu.com/project/docs/SRU/reference/exception-OpenStack-Updates/`), the SRU bug template
(`…/SRU/reference/bug-template/`), the SRU overview (`…/SRU/stable-release-updates/`), and the tracker precedent LP #2167438.

| Question | Answer |
|---|---|
| Ubuntu bug required? | Yes: an SRU needs a bug in the template (Impact, Test Plan, Where problems could occur, Other Info). For the OpenStack point release the template differs (Impact, Test Case, Regression Potential, Discussion), as in #2167438 |
| Source package / series | `neutron` (source), Ubuntu 26.04 "resolute"; `cloud-archive/gazpacho` tracks the noble UCA pocket and is not needed for Hagistack, but the OpenStack team follows "upstream → Ubuntu → UCA" order |
| Fix in the devel release first? | Yes, required: met by stonking `2:29.0.0~rc1-0ubuntu1` (verified from source) |
| Upstream stable acceptance? | Preferred, not mandated for an individual cherry-pick: the OpenStack page says "Bugs must be fixed in the following order, when possible: upstream…, Ubuntu release…, UCA…" and "only" point releases, high-impact bugs, or obviously safe patches. A merged stable/2026.1 change makes the fix arrive through the point-release vehicle |
| Package delta shape | Two quilt/gbp patches under `debian/patches` with DEP-3 headers (cherry-picks of `83f1d830`, `91abb5e7` in that order), `debian/patches/series` entries, `debian/changelog` entry, version `2:28.0.2-0ubuntu1.1` (same shape as `2:28.0.0-0ubuntu1.1`), optionally an autopkgtest addition (an existing `debian/tests/neutron-api` already installs `neutron-ovn-maintenance-worker` and `ovn-central`) |
| Normal distro patches? | Yes; applies cleanly to 28.0.2 and to Ubuntu's patch series (their patches touch other files) |
| Version bump? | Yes (above) |
| Regression potential | four files; changes when the maintenance lock is requested; `RpcWorker` and direct callers must keep not requesting it (covered by the matrix in §7.4); upgrade path: the maintenance worker restarts on package upgrade |
| Verification | installed from `-proposed` on a real OVN host; tests per §13; OpenStack team runs its CI/Tempest before `verification-done`; minimum aging 7 days in `-proposed` |

`UBUNTU SRU: READY TO PREPARE` (the bug text, patch shape and test plan can be written now; acceptance, upload and timing are **[EXTERNAL]**; the preferred vehicle still waits on upstream)

## 13. Safe validation requirements (Ubuntu reproduction / SRU verification)

The test must be **passive**. Required:
1. Never issue a `lock` (or `steal`) request for `ovn_db_inconsistencies_periodics` from any test helper, including `ovsdb-client lock`.
   A waiter that connects and disconnects makes ovsdb-server re-send `locked` to the owner, which heals a stuck worker and invalidates the
   observation [PRIOR, reproduced on two hosts and in-process].
2. Observe only with read-only instruments: loopback packet capture of the NB port, `ss`/`/proc` sampling, the Neutron and journal logs, `systemctl show`.
3. Detect F-NEW-1 per worker start from the current process tree only: the worker sent `lock`, the server replied `{"locked": true}`, and within 60 s of
   "MaintenanceWorker process has finished the post initialization" the same tree logs repeated "configured to require a database lock" errors / failed
   `@has_lock_periodic` tasks while the unit is active.
4. Verify from the capture that every `lock` request on the wire came from a maintenance-worker session (as the Rocky runtime remediation did).
5. The natural rate is ~6 % per start (4/66 on 28.0.2), so the unpatched case needs many starts: at p = 0.06, P(≥1 affected) ≈ 95 % in 50 starts and ≈ 99.8 % in 100. A clean patched run is statistical only. A widened-window harness that patches python-ovs is a mechanism illustration, not a deployment test.
6. Also check that RPC-worker NB sessions send no `lock` (capture) on the patched package.

**Review of the existing plans:** no validation method in the reassessment, the preparation, or the harness uses an external waiter or
`ovsdb-client lock` as an observer. The text "recovered when a separate lock waiter made the server re-notify the owner" is a recorded
observation, not a method. The reassessment lists "lock waiter" only as a workaround class (Option G). The Ubuntu product script and tests contain no
`ovsdb-client lock` (the historical occurrences are in the committed WP-A evidence report). **No correction is needed**, but the five rules above must be written into any future Ubuntu test case.

## 14. External-lock-nudge prohibition

Stated as a hard requirement: no accepted Ubuntu evidence may involve an external lock waiter or any client that requests the maintenance lock name,
except the two real maintenance workers used for the handover scenario. The same rule already applies to the accepted Rocky runtime evidence
(`EXTERNAL LOCK NUDGE USED: NO`).

## 15. Deferred and out of scope

`O-A: DEFERRED / SEPARATE` (fresh-install/systemd/config timing), `F13b: DEFERRED`, `python333/python3333: DEFERRED`,
`TAG_REQUEST FINDING: DEFERRED / SEPARATE` (`a8feb94e`), `c695003d: DEFERRED / SEPARATE` (optional, conflicts in BGP on stable/2026.1),
unrelated RabbitMQ and Nova shutdown noise: not addressed, `CLIFF: DEFERRED`. Not dependent on any of them: no causal dependency was found.
stable/2025.2 and 2025.1 have the same defect but are not prepared.

## 16. Exact next action

**EXACT NEXT ACTION:** a human contributor with OpenDev Gerrit access submits the prepared two-change stack to `openstack/neutron` `stable/2026.1`
(Change 1 then Change 2, rebased onto `29d4ee42e2`, real committer identity, first review comment repeating that the pair must merge together and
citing LP #2155155/#2156979). This needs explicit authorisation from the project owner and is the only step that moves Ubuntu toward closure without a
package-model change. After it is up, open the Ubuntu `neutron (Ubuntu)` SRU bug referencing it; do not file either from this task.

## 17. Mutation summary

- Hagistack: product, tests, docs, Rocky files, earlier reports: 0 changed; nothing staged or committed; both input reports unmodified.
- Upstream: fetch-only; the disposable clone holds local branches; no push, no `git review`, no Gerrit or Launchpad change.
- Ubuntu: no package built, no bug, no upload. GCE: not touched. No secrets seen.
- Local additions outside the repository: a symlink `/private/tmp/hgdg` → the evidence directory; the earlier symlink `/private/tmp/hgnp` is reused read-only for the test venv.

## 18. Freshness re-check (2026-09-30T23:39Z)

This decision gate was requested again; the external state was re-queried before re-issuing the result. **No decision-relevant change**:

- stable/2026.1 HEAD still `29d4ee42e2`; `83f1d830`, `91abb5e7`, `c695003d` absent; their Change-Ids and bug numbers: 0 hits in stable/2026.1 history.
- Gerrit: still one MERGED master change per Change-Id; 0 stable/2026.1 changes for either bug or mentioning `MaintenanceWorker`; 0 open `openstack/releases` changes for Neutron.
- Ubuntu: resolute Neutron still `2:28.0.2-0ubuntu1` (Updates 2026-09-24; Proposed same upload); upload queues New/Unapproved/Accepted empty.
- Launchpad: #2155155 and #2156979 unchanged (last activity 2026-07-16, single `neutron` task each); no new `neutron (Ubuntu)` task since 2026-09-30; no `lock` / `NOT_LOCKED` / `maintenance worker` hit in `neutron (Ubuntu)` or `cloud-archive` since 2026-09-29.
- stable/2026.2 advanced by two commits (`7121bf4262` → `1b5bd26585`): the same DNS maintenance-task backport (`b58c3d7e90` and its merge). It adds a task to `maintenance.py` (and its test) but changes no lock-related line.
- Hagistack: HEAD `dd752d4`, nothing staged, no tracked change; the two input reports byte-identical to the previous gate.

The result in §16 and the final block stand unchanged.

UBUNTU F-NEW-1 RESOLUTION DECISION: DECISION READY
UBUNTU DISTRO-PACKAGE MODEL: PRESERVABLE AFTER EXTERNAL ACTION
STABLE/2026.1 BACKPORT: READY TO SUBMIT
UBUNTU SRU: READY TO PREPARE
ROCKY F-NEW-1 ROOT FIX: CLOSED
UBUNTU WP-A STATUS: HOLD
WP-A MERGE: HOLD
PRODUCT MUTATIONS: ZERO
STAGED/COMMITTED: NONE
PUSH/PR/TAG/RELEASE: NONE
