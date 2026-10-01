# F-NEW-1 on Ubuntu 26.04: resolution reassessment

Read-only research, 2026-10-01. **Untracked and unstaged by design.** Nothing was
implemented, patched, packaged, submitted or filed. Research checkouts and
downloads are in
`/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-ubuntu-reassessment-2026-10-01/`
(fresh `neutron` clone, Ubuntu source packages, ovs/ovsdbapp sources).

Labels: **[PRIOR]** established in an earlier report and not re-derived,
**[FRESH]** verified today against the authoritative source, **[INFERENCE]**
my reading, not a recorded fact.

---

## Conclusions

- **The Ubuntu 26.04 package still does not contain the F-NEW-1 fix, and
  nothing is in flight.** `neutron 2:28.0.2-0ubuntu1` (resolute-updates,
  2026-09-24) is unchanged. Its maintenance/OVSDB files are byte-identical to
  upstream 28.0.2. No newer Neutron is in resolute-proposed or any upload queue.
- **stable/2026.1 still lacks the fix.** Not merged, not proposed, not
  mentioned in any stable/2026.1 Gerrit change. The branch moved by one
  unrelated commit since September.
- The minimal root fix is unchanged: **`83f1d830` then `91abb5e7`**. On the
  current stable/2026.1 head the pair applies cleanly in that order; `91abb5e7`
  alone conflicts; `c695003d` conflicts in BGP code.
- The fix already exists in the **Ubuntu development series** (stonking,
  `neutron 2:29.0.0~rc1-0ubuntu1`), which satisfies the SRU prerequisite "fix
  is in the development release".
- No evidence of progress toward 26.04 exists: no Launchpad task on any series,
  no Ubuntu bug, no backport discussion, no stable review.
- The Ubuntu distro-package model can be preserved, but only by an **active**
  upstream contribution followed by an Ubuntu update. Passive waiting has no
  supporting evidence. A custom Ubuntu package is **not** required today.

---

## A. Preflight

| | |
|---|---|
| branch | `fix/rocky-neutron-maintenance-lock` |
| HEAD | `207795084855e0fa7e3bce7124d4f0440408cfd4` ("docs: record Rocky maintenance lock acceptance") |
| origin/master | `7a20dbe1ba8cde14f9e35252e1f9074387d695d6` |
| Rocky product candidate | `40472e879bf55d66fb4f3ecb719d67fb180567d6`, ancestor of HEAD |
| HEAD vs candidate | HEAD adds only `acceptance/F-NEW-1_ROCKY_BACKPORT_ACCEPTANCE_2026-09-30.md` |
| staged | none |
| tracked modifications | none |
| untracked (before this report) | `AGENTS.md` and 8 `acceptance/F-NEW-1_*.md` reports |

Product files relevant to Ubuntu WP-A (worktree SHA-256; HEAD blob equals
worktree blob equals `cb3154a` blob for the two WP-A code paths):

| File | SHA-256 |
|---|---|
| `ubuntu26.04/hagistack` (blob `274fa065…`) | `81c4e62685a92f3264051890b518c3dcc3be0710483fe9d86acc83f4b0ed6559` |
| `ubuntu26.04/tests/container-step4.sh` (blob `5253c12d…`) | `c66f88bb832cbd216131f8d342f9c9d48782a377c21f13fe2cefc74b22fb66c3` |
| `ubuntu26.04/README.md` | `c42d41f2c9483234ce03c3e82f4f5575fe48b84b2a217b62f0b19e1719501b1b` |
| `ubuntu26.04/README.ja.md` | `c5a84dffe0c9472ae8b272ae48768d4c5ca64b309f6ece3597fcd3175b9a2b8f` |
| `README.md` / `README.ja.md` | `cda0ed3d…8b` / `92375c09…458` |

Rocky verdict, from the final recheck report
(`F-NEW-1_ROCKY_RUNTIME_EVIDENCE_INDEPENDENT_RECHECK_2026-10-01.md`, §W, read
only, nothing rerun): "ROCKY F-NEW-1 ROOT FIX: INDEPENDENT AUDIT PASS /
CLOSED", new blocking findings 0, "UBUNTU WP-A STATUS: HOLD". No contradiction
found.

`ROCKY F-NEW-1 ROOT FIX: CLOSED / FROZEN`

`REASSESSMENT PRODUCT MUTATIONS: ZERO`

## B. Existing causal baseline [PRIOR]

From the investigation (§Q) and feasibility report (§C), cross-checked today
against the Ubuntu-shipped sources:

- `DBInconsistenciesPeriodics.__init__` calls `self._idl.set_lock(...)` from the
  worker's main thread (Ubuntu source, `maintenance.py:235`).
- ovsdbapp `Connection.start()` has already run `wait_for_change()` and started
  the connection thread, which loops `with self.lock: idl.run()`
  (`connection.py`, 2.16.0). `set_lock` runs without that lock.
- python-ovs 3.7.1 `set_lock` → `__send_lock_request` does
  `self._lock_request_id = self.__do_send_lock_request("lock")`, so the request
  id is stored **after** the send returns (`idl.py` `__do_send_lock_request`,
  `__send_lock_request`). `run()` matches the reply only when
  `_lock_request_id == msg.id` (`idl.py:562-563`).
- A fast reply processed by the connection thread in that window is dropped.
  The server considers the worker the owner; python-ovs has
  `has_lock=False`, `is_lock_contended=False`, and refuses writes (`NOT_LOCKED`).
  Neutron's `has_lock = not is_lock_contended` still says "owner".
- Natural rate on Ubuntu: 4 of 66 starts [PRIOR].

`F-NEW-1 ROOT CAUSE BASELINE: CONFIRMED`

## C. Upstream fixes [FRESH]

Fresh clone of `https://opendev.org/openstack/neutron` today:
master `97f4dadd06`, stable/2026.2 `7121bf4262` (29.0.0-5), stable/2026.1
`8c1075228f` (28.0.2-18).

| Commit | Author, date | Subject | Change-Id | Bug | Gerrit |
|---|---|---|---|---|---|
| `83f1d8305651a0ab23629c88d70bfa237055158c` | Terry Wilson, 2026-06-09 | Ensure MaintenanceWorker lock set before connect | `Iaefe1e2cc86ddd55c9053fde66353b2a333e1e98` | Related-Bug #2155155 | 992569 |
| `91abb5e720e1c515dbfbe9b2313fbdff92b2abbf` | Terry Wilson, 2026-06-17 | Only set the maintenance worker lock on the worker | `I74145ef1407856b7ec75de87daa2270b452b6c70` | Closes-Bug #2156979 | 993860 |
| `c695003d1012b911aa7c3f604d6d169d2567521c` | Rodolfo Alonso Hernandez, 2026-06-03 | Use idl.has_lock instead of idl.is_lock_contended for OVSDB lock checks | `I80e74a399b7c3420baf49e0cbc50ddfee0a070e0` | Closes-Bug #2155155 | 991346 |
| `a8feb94e411431e084adaa9e8ee1724cc3ff1b6f` | Terry Wilson, 2026-06-12 | More tag_request fixes | (not needed) | Related-Bug #2155155 | 993186 |

All identities match the September record. All are merged in master and
stable/2026.2, in tags `29.0.0.0b1`, `rc1`, `rc2` and `29.0.0`. `a8feb94e`
is in master and stable/2026.2 only, and is about `tag_request` in
`commands.py`/`ovn_client.py`. It is unrelated to the lock.

**Commit-message fact:** `83f1d830` describes its purpose as removing a window
where "tasks might fire and fail and have to be retried". It does **not**
describe the permanent dropped-reply state. [INFERENCE] Stable reviewers may
therefore read it as a minor robustness change; the persistent `NOT_LOCKED`
evidence is what justifies a backport.

`MINIMAL F-NEW-1 ROOT FIX: 83f1d8305651a0ab23629c88d70bfa237055158c + 91abb5e720e1c515dbfbe9b2313fbdff92b2abbf` (unchanged; always together, `83f1d830` first)

- Reason `91abb5e7` is part of it [PRIOR, reconfirmed by reading the 2026.1
  tree]: stable/2026.1 contains `bba77b6ece` (2026-06-30, "rpc/ovn: Use base OVN
  IDL for RPC workers"), so `from_worker` puts `RpcWorker` in the same branch
  as `MaintenanceWorker`. `83f1d830` alone would make every RPC worker request
  the maintenance lock. `91abb5e7` keys the call on `worker_class.lock_name`.
- `c695003d` remains defensive and separate (changes the meaning of `has_lock`;
  alone it would turn the stuck state into silent never-maintaining).
- Nothing changed upstream about this set.

## D. stable/2026.1, current status [FRESH]

| Fix | master | stable/2026.2 | stable/2026.1 | proposed review | status/date |
|---|---|---|---|---|---|
| `83f1d830` (992569) | merged 2026-06-10 | merged | **absent** | none | merged on master; no stable review |
| `91abb5e7` (993860) | merged 2026-06-18 | merged | **absent** | none | same |
| `c695003d` (991346) | merged 2026-06-10 | merged | **absent** | none | same |
| `a8feb94e` (993186) | merged 2026-06-15 | merged | absent | none | separate topic |

How it was checked:
- `git log origin/stable/<x> --grep=<Change-Id>` for all three Change-Ids:
  empty on 2026.1; one hit each on 2026.2 and master.
- Content check of stable/2026.1 files: `maintenance.py` still has
  `self._idl.set_lock(MAINTENANCE_NB_IDL_LOCK_NAME)` (line 235) and
  `has_lock = not self._idl.is_lock_contended` (line 299); `impl_idl_ovn.py` has
  no `set_lock`/`lock_name`; `mech_driver.py` has no `lock_name`. On
  stable/2026.2 `impl_idl_ovn.py:251` has `idl_.set_lock(worker_class.lock_name)`
  and `has_lock` returns `self._idl.has_lock`.
- Gerrit (`review.opendev.org`): each Change-Id resolves to exactly one change,
  on master, MERGED. `branch:stable/2026.1` with `bug:2155155` or `bug:2156979`:
  0 changes. Text search for "lock" and "MaintenanceWorker" on stable/2026.1
  finds only an unrelated merged change (1002368). The five open stable/2026.1
  changes (1008035, 1007629, 1006082, 1002462, 1007630) are unrelated.
- New commits on stable/2026.1 since the September snapshot: one,
  `8c1075228f` (2026-09-14, "Keep allocated VLAN registers when purging a
  physical network"), unrelated. No 28.0.3 tag exists (latest 28.0.2).

`STABLE/2026.1 CONTAINS MINIMAL ROOT FIX: NO`

## E. Launchpad bug status [FRESH]

| | LP #2155155 | LP #2156979 |
|---|---|---|
| title | OVN maintenance worker uses is_lock_contended instead of has_lock… | neutron-ovn-db-sync-util repair mode fails with OVSDB lock error after "Ensure MaintenanceWorker lock set before connect" |
| tasks | one: `neutron`, Fix Released, Medium | one: `neutron`, Fix Released, High |
| released | 2026-06-10; milestone 29.0.0.0b1 | 2026-06-18; milestone 29.0.0.0b1 |
| 2026.1 series task | **none** | **none** |
| Ubuntu task | **none** | **none** |
| comments | 7, the last on 2026-07-16 (bot: "fixed in 29.0.0.0b1") | 6, the last on 2026-07-16 (same) |
| new since September | **none** | **none** |

FACT: there is no backport or SRU discussion on either bug, no maintainer
rejection and no acceptance. No Ubuntu `neutron`, `python-ovsdbapp` or
`openvswitch` bug matches "lock", "NOT_LOCKED", "is_lock_contended",
"ovn_db_inconsistencies", "set_lock", "2155155" or "2156979" (the hits are
unrelated bugs from 2014–2022).

INFERENCE: silence means nobody has proposed it, not that it was refused. The
bugs also do not describe the persistent-stuck symptom, so the upstream project
may not know that `83f1d830` is more than a robustness change.

## F. Ubuntu archive status [FRESH]

Launchpad `getPublishedSources`, Ubuntu primary archive, series resolute
(26.04, released 2026-04-23):

| Source | Version | Pocket | Status | Published |
|---|---|---|---|---|
| neutron | **2:28.0.2-0ubuntu1** | Updates | Published | 2026-09-24 |
| neutron | 2:28.0.2-0ubuntu1 | Proposed | Published (same upload) | 2026-09-16 |
| neutron | 2:28.0.0-0ubuntu1.1 | Updates | Superseded | 2026-09-02 |
| neutron | 2:28.0.0-0ubuntu1 | Release | Published | 2026-04-07 |
| python-ovsdbapp | 2.16.0-2 | Release | Published | 2026-03-27 |
| openvswitch (python3-openvswitch) | 3.7.1-2 | Release | Published | 2026-04-16 |
| ovn | 26.03.0-2 | Release | Published | 2026-04-16 |
| python-neutron-lib | 3.24.0-2 | Release | Published | 2026-03-26 |

- No Security or Backports pocket publication of `neutron` exists for resolute.
- No newer `neutron` in resolute-proposed. Upload queues
  (New/Unapproved/Accepted/Rejected) for `neutron` in resolute are empty; Done
  shows only the uploads above.
- Source identity: `neutron_28.0.2-0ubuntu1.dsc`
  `1fe00fb84f2c1da6c1f8057eac9f17b2c6626cd1ea7c8320c07403831ee685ce`;
  `neutron_28.0.2.orig.tar.gz`
  `cdaf45a2100de5233e4c1cc7c01c9df2b634510a0f0436913f73f29d42d325ee`;
  `neutron_28.0.2-0ubuntu1.debian.tar.xz`
  `bb1434e7251069c22a17ded2f8d359ea89d450bb9a87b4e7237f58c821d85868`.
  The orig tarball hash equals the September record and the Rocky pin.
- The currently published version changelog
  ("New upstream stable release for OpenStack Gazpacho (LP: #2167438)") was
  prepared from upstream tag 28.0.2; LP #2167438 is Fix Released on
  resolute and `cloud-archive/gazpacho`.

`CURRENT UBUNTU 26.04 NEUTRON VERSION: 2:28.0.2-0ubuntu1 (resolute-updates, published 2026-09-24; source package neutron; unchanged since the September research)`

## G. Ubuntu source inspection [FRESH]

Unpacked the current orig + debian tarballs and applied the series
(`install-missing-files.patch`, `skip-iptest.patch`,
`lp2150285-keep-mod-wsgi-operational.patch`, all applied cleanly in order).

- Patches touch only `MANIFEST.in`, `neutron/common/wsgi_utils.py`, and two
  unit tests. **None touches** any OVN, maintenance or lock file.
- SHA-256 prefixes, Ubuntu-patched tree = pristine orig = upstream tag 28.0.2:

  | File | Prefix |
  |---|---|
  | `…/mech_driver/ovsdb/maintenance.py` | `22baf6d9dc69afb1` |
  | `…/mech_driver/ovsdb/impl_idl_ovn.py` | `0d305cc2f2401c0a` |
  | `…/mech_driver/mech_driver.py` | `f53edc1ee2e82a94` |
  | `neutron/common/ovn/constants.py` | `a31fe4548bbf6b2b` |

- Source greps in the Ubuntu-patched tree: `maintenance.py` still defines
  `MAINTENANCE_NB_IDL_LOCK_NAME`, still calls
  `self._idl.set_lock(MAINTENANCE_NB_IDL_LOCK_NAME)` in
  `DBInconsistenciesPeriodics.__init__`, and `has_lock` is still
  `not self._idl.is_lock_contended`. `impl_idl_ovn.py` and `mech_driver.py`
  contain no `set_lock` or `lock_name`.
- Equivalent fix under another identity: none. The d/changelog entries of the
  two most recent uploads do not mention any lock change.

So `83f1d830`-equivalent: absent. `91abb5e7`-equivalent: absent. `c695003d`:
absent.

`UBUNTU PACKAGE CONTAINS MINIMAL F-NEW-1 ROOT FIX: NO`

## H. Proposed and SRU status [FRESH]

- resolute-proposed holds only the already released 28.0.2 upload. Nothing is
  pending migration, and there is no blocker to report because there is no
  candidate.
- Ubuntu bugs on `neutron (Ubuntu)`: the most recent are #2156587 (haproxy
  metadata proxy 502, Fix Released 2026-09-18) and the point-release bug
  #2167438. None concerns the lock.
- Changelog/branch: Ubuntu's packaging repository has no unreleased
  resolute entry; the `applied/ubuntu/resolute-updates` changelog head is
  28.0.2-0ubuntu1.
- Ubuntu **development** series (stonking, 26.10, "Pre-release Freeze"):
  `neutron 2:29.0.0~rc1-0ubuntu1`, published 2026-09-16. Built from upstream
  `29.0.0~rc1`, which contains all three commits (`29.0.0.0rc1` tag contains
  them). [FACT] for the version and the upstream tag; that stonking therefore
  carries the fix is [INFERENCE] from the tag, not a source inspection of the
  stonking package.
- Out of scope but noted: the `ubuntu-cloud-archive/hibiscus-staging` archive
  holds `2:29.0.0~rc1-0ubuntu1~cloud0` for resolute. It is a staging archive, a
  different OpenStack release (2026.2) and a different repository; it is not one
  of the options A–G and was not evaluated.

`UBUNTU SRU FOR F-NEW-1: NOT FOUND`

## I. Dependency inspection [FRESH]

Current Ubuntu 26.04: `python3-ovsdbapp 2.16.0-2`, `python3-openvswitch 3.7.1-2`
(both Release, no -updates). Unchanged from September.

- **python-ovs 3.7.1 (`python/ovs/db/idl.py`)**: `set_lock` → `__send_lock_request`
  stores the request id after the send; `run()` compares the reply id with
  `_lock_request_id`. Same logic on upstream OVS `main` (the `set_lock` bodies
  are identical by diff). No dependency change closes the window.
- **ovsdbapp 2.16.0 `Connection.start()`**: `wait_for_change()` runs in the
  caller's thread, then the connection thread starts. Neutron's pre-fix
  `set_lock` call happens after that.
- **ovsdbapp master** differs from 2.16.0 only by `_check_lock_change()` and a
  `notify_lock` hook (plus dropping a Windows import). It adds a
  `has_lock`-transition notifier and relies on the lock being requested before
  `start()` ("wait_for_change() drains the initial messages, including any lock
  reply"). It does not change the id bookkeeping or add any locking around
  `set_lock`. It is not in the Ubuntu archive.
- Debian packaging of python-ovsdbapp carries only `install-missing-files.patch`;
  openvswitch 3.7.1-2 carries no patch directory.
- neutron-lib 3.24.0-2 is the Ubuntu version; stable/2026.1 requires
  `neutron-lib>=3.24.0`. `RpcWorker` having no `lock_name` (the premise of
  `91abb5e7`'s guard) is [PRIOR].

`DEPENDENCY UPDATE ELIMINATES F-NEW-1 WITHOUT NEUTRON PATCH: NO`

The race is the ordering of Neutron's `set_lock` versus the connection thread.
Only the Neutron change (or a lock around `set_lock` in python-ovs/ovsdbapp,
which does not exist) removes it.

## J. Stable backport feasibility [FRESH]

Simulated with `git merge-tree --write-tree` (object-level three-way merge in
the research clone; no cherry-pick command, no patch file, no working tree)
against stable/2026.1 `8c1075228f`:

| Change(s) | Result |
|---|---|
| `83f1d830` | clean |
| `83f1d830`, then `91abb5e7` | **clean** (4 files, +8/−3; `constants.py`, `mech_driver.py`, `impl_idl_ovn.py`, `maintenance.py`); all four compile |
| `91abb5e7` alone | **conflict** in `impl_idl_ovn.py` |
| `c695003d` | conflict in `neutron/services/bgp/reconciler.py` (maintenance.py merges automatically) |
| `c695003d` after the pair | same BGP conflict |

- Order: `83f1d830` first, then `91abb5e7`. They are a pair: `83f1d830` alone
  on 2026.1 makes RPC workers lock (`bba77b6ece` is on the branch), and
  `91abb5e7` alone does not apply. Submit both together, reviewable as a
  two-change series, and say so in the commit context.
- `c695003d` should stay separate. Its BGP hunk needs manual resolution because
  stable/2026.1 lacks master's startup-wait code there.
- Policy (docs.openstack.org/project-team-guide/stable-branches): a change must
  already be merged on master and newer stable branches (satisfied: master and
  stable/2026.2); use `git cherry-pick -x`; keep the original Change-Id; two
  stable-maintainer +2s; 2026.1 is in the Maintained phase. The fix is a bug
  fix, not a feature, API, DB schema or config change.
- Tests: upstream added none for `83f1d830`/`91abb5e7` [PRIOR]. No unit or
  functional suite was run here. `py_compile` and the mechanical merge are not a
  test pass. The real-class harness from September is the verification
  material [PRIOR].
- Whether the reviewers accept it is not established.

`STABLE/2026.1 BACKPORT TECHNICALLY FEASIBLE: YES`

## K. Ubuntu SRU feasibility [FRESH, process docs]

Sources: Ubuntu "Stable Release Updates for OpenStack and the Ubuntu Cloud
Archive" (documentation.ubuntu.com/project/SRU) and the SRU bug template.

- Target: source package `neutron`, release resolute, pocket resolute-proposed
  → resolute-updates. `openvswitch` and `ovn` are also covered packages, but
  the change is in `neutron`.
- Prerequisite: the fix must already be in the development release. Stonking has
  Neutron 29.0.0~rc1 (Section H), so this is met (by inference from the tag).
- Order required by Ubuntu's OpenStack process: upstream (latest release) first,
  then the corresponding Ubuntu release, then UCA. Both upstream steps exist
  for 2026.2; the stable/2026.1 step is not done.
- Preferred vehicle: upstream stable point releases ("New upstream stable point
  releases for OpenStack core packages which group several bug fixes together").
  Individual cherry-pick SRUs are for high-impact bugs (security, severe
  regression, data loss) or patches with an obviously safe profile. That is how
  28.0.2 arrived (tag 2026-09-10 → updates 2026-09-24, about two weeks).
- Bug requirements: Impact, Test Plan, "Where problems could occur" (never
  "None"/"Low"), Other Info. The test plan for a ~6 % thread race has no
  upstream test and needs a harness; regression potential is narrow (four
  files, changes when the maintenance lock is requested).
- An upstream stable/2026.1 merge would materially help acceptance: it makes
  the fix part of the next stable point release (the preferred vehicle) and
  removes the need for an Ubuntu-only cherry-pick.
- Not established: whether the Ubuntu OpenStack team would accept an individual
  cherry-pick for this bug, or when the next 28.0.x would be tagged.

`UBUNTU SRU TECHNICALLY FEASIBLE: YES`
(mechanically feasible; acceptance and timing are UNKNOWN)

## L. Option matrix

| Option | Current factual availability | Preserves Ubuntu distro-package model? | Root fix? | Hagistack product change required? | External dependency | Current blocker |
|---|---|---|---|---|---|---|
| **A** Normal Ubuntu package already fixed | **No.** 28.0.2-0ubuntu1 lacks it (Section G) | yes | n/a | none | none | package not fixed |
| **B** Fix in proposed, normal migration | **No.** Nothing in resolute-proposed or upload queues | yes | n/a | none | Ubuntu migration | no candidate exists |
| **C** stable/2026.1 backport exists, Ubuntu hasn't published it | **No.** No backport exists or is proposed | yes | n/a | none | upstream stable + Ubuntu | backport does not exist |
| **D** Propose upstream stable backport first | **Possible today**: pair applies cleanly (Section J) | yes | yes, after merge and release | none | stable maintainers; next 28.0.x; Ubuntu point-release SRU | not yet proposed; no evidence anyone intends to |
| **E** Request Ubuntu SRU directly | Mechanically possible; prerequisite met via stonking | yes | yes, after acceptance | none | SRU team; OpenStack team | acceptance uncertain (policy prefers point releases); needs test plan |
| **F** Hagistack-owned Ubuntu package | Technically available immediately (clean apply) | **no** | yes | large (build, repo, versioning, signing, security tracking) | none, but Hagistack becomes maintainer | needs an explicit project-level decision |
| **G** Runtime workaround (health check, restart, log parsing, lock waiter) | Possible | yes (packages unchanged) | **no** | yes (new behaviour) | none | partial only: does not cover reboot, manual, package or crash restarts; re-rolls a ~6 % race; the feasibility report classified this a temporary mitigation |

D and E are compatible and can run in parallel. No scoring.

## M. Packaging-model decision

Rocky owns and builds its RPMs, so carrying the pair there was within model
(closed). Ubuntu uses archive packages, and that distinction is a design
constraint, not an accident. Every sustainable distro route (A, B, C) is
currently empty. The remaining distro-sustainable routes (D, E) exist but have
not been started. Nothing forces F today: WP-A Ubuntu is on HOLD, nothing runs
in production, and no deadline in the evidence requires an Ubuntu Neutron
before an upstream/Ubuntu fix can land.

- Ubuntu's own fixed Neutron exists for the development series only.
- Passive waiting: **no evidence of progress** (no bug task, no review, no
  upload, no discussion). Waiting is reasonable only after D or E has been
  started.

`WAIT FOR OFFICIAL PACKAGE: NO EVIDENCE OF PROGRESS`

`UBUNTU DISTRO-PACKAGE MODEL CAN BE PRESERVED NOW: WAIT`

(The model survives, but the root fix is not obtainable from it today. The
September "NO" stands as to availability; "WAIT" adds that preserving the model
depends on starting D/E rather than idling.)

`CUSTOM UBUNTU PACKAGE REQUIRED TODAY: NO`

Not required because D/E are open and unexhausted, and because F changes
ownership, update and security-maintenance responsibility, provenance, release
process and long-term burden. That is a separate project decision, not an
incidental F-NEW-1 fix. Option F is not recommended; it is held as the last
resort should D and E be refused or stall.

## N. Next action (one, bounded)

**Decision C of §24: stable/2026.1 still lacks the fix. Prepare the upstream
stable backport contribution as a separate action**, for the pair
`83f1d830` then `91abb5e7`, with `c695003d` left out or as a separate change:

- cherry-pick with `-x`, original Change-Ids kept, against stable/2026.1
- reference LP #2155155 and #2156979; ask for a 2026.1 series task
- state in the review that `83f1d830` must not merge without `91abb5e7` on
  2026.1, and include the persistent-`NOT_LOCKED` evidence (4/66 starts, real
  class harness) because the upstream commit messages do not describe it
- afterwards, request the Ubuntu update through the next point release, or an
  SRU bug with the template in Section K

This reassessment does not perform or authorise any submission. Nothing is
filed. Ubuntu WP-A stays on HOLD until a fixed Ubuntu package exists and is
independently validated on Ubuntu.

## O. Deferred findings

- `O-A: DEFERRED / SEPARATE` (fresh-install start/restart timing and
  same-second config mtime comparison; not touched)
- `TAG_REQUEST FINDING: DEFERRED / SEPARATE` (`a8feb94e`; not touched)
- `F13b: DEFERRED`
- `CLIFF: DEFERRED`

## P. Mutation summary

- product files modified: 0; tests: 0; docs: 0; spec patches: 0; manifests: 0
- staged: 0; commits: 0; pushes: 0; PRs: 0; tags/releases: 0; merges: 0
- existing evidence reports overwritten: 0 (SHA-256 of all nine
  `F-NEW-1_*.md` compared before and after)
- Rocky: not rebuilt, not revalidated, F-NEW-1 not reopened
- no cherry-pick command, no patch file, no Gerrit or Launchpad submission, no
  Launchpad bug filed, no PPA, no package built, no proposed pocket enabled
- no GCE resource, VM or container touched or created
- one new untracked file: this report
- external research data under
  `/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-ubuntu-reassessment-2026-10-01/`
  (fresh upstream clone with merge-tree objects, Ubuntu source downloads, ovs
  and ovsdbapp sources). Kept for review; no secrets encountered.

`REASSESSMENT PRODUCT MUTATIONS: ZERO`

## Q. Overall status

`ROCKY F-NEW-1 ROOT FIX: CLOSED`

`UBUNTU WP-A STATUS: HOLD`

`WP-A MERGE: HOLD`

---

ROCKY F-NEW-1 ROOT FIX: CLOSED
UBUNTU DISTRO-PACKAGE MODEL CAN BE PRESERVED NOW: WAIT
CUSTOM UBUNTU PACKAGE REQUIRED TODAY: NO
UBUNTU F-NEW-1 ROOT FIX: NOT AVAILABLE
UBUNTU WP-A STATUS: HOLD
WP-A MERGE: HOLD
HAGISTACK UBUNTU F-NEW-1 REASSESSMENT: DECISION READY
