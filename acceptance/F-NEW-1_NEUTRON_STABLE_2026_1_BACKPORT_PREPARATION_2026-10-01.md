# F-NEW-1: Neutron stable/2026.1 upstream backport, local preparation

Local preparation and validation, 2026-09-30/10-01 (UTC). **Nothing was pushed,
submitted, filed or sent to anyone.** **Untracked and unstaged by design.**

Raw evidence and the review package:
`/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-neutron-stable-backport-prep-2026-10-01/package/`
(231 files + `SHA256SUMS`, which itself hashes to
`f0fe75c46273219c6393c4317e56fa2f27d9af85f3f5887cd9bda1d913d952d8`). The disposable
Neutron checkout with the local branches is `…/neutron/` in the same directory.

Labels: **[PRIOR]** taken from earlier Hagistack reports, **[FRESH]** verified in
this task, **[INFERENCE]** reading, not a recorded fact.

---

## Conclusions

- stable/2026.1 (`8c1075228f`) still lacks the fix. Two local commits, both
  clean `git cherry-pick -x` results, sit on it: **Change 1** `46256f84578d…`
  (`83f1d830`), **Change 2** `91bb432c5c34…` (`91abb5e7`). No third commit, no
  merge commit, `c695003d` and `a8feb94e` absent.
- Changed lines are identical to the master commits. Context differs only
  because stable/2026.1 already has the RPC-worker change `bba77b6ece`.
- **Change 1 alone is unsafe on stable/2026.1** (demonstrated): an RPC worker
  requests the maintenance lock, and when it starts first the real maintenance
  worker is left contended with failing writes.
- **Change 1 + Change 2 removes the race** under the widened deterministic
  window: stable/2026.1 10/10 stuck with 10 NOT_LOCKED write failures, the
  series 0/10. RPC workers request no lock; the maintenance worker requests it
  on every start.
- Targeted unit set (1049 tests): identical result on base, Change 1 only and the
  series (1046 passed, 3 skipped, 0 failed). The full unit suite shows the same
  three platform failures on base and series plus a flaky
  `TestNovaSegmentNotifier` class that fails on the unmodified base too.
- Limitations an auditor must weigh are in §V: the OVSDB peer in the
  deterministic harness is a protocol stub, not ovsdb-server (no Linux runner
  was authorised for this task), and upstream functional jobs were not run.

---

## A. Preflight

| | |
|---|---|
| Hagistack branch / HEAD | `fix/rocky-neutron-maintenance-lock` / `207795084855e0fa7e3bce7124d4f0440408cfd4` (unchanged) |
| origin/master (Hagistack) | `7a20dbe1ba8cde14f9e35252e1f9074387d695d6` |
| staged / tracked modifications | none / none; untracked: `AGENTS.md`, nine earlier `acceptance/F-NEW-1_*` reports, this report |
| Neutron upstream remote | `https://opendev.org/openstack/neutron` (fetch only; clone made 2026-09-30T21:24:40Z–21:25:19Z, clean) |
| stable/2026.1 HEAD (base) | `8c1075228f41a95351567be57f5bfb3ff8146ed2` (2026-09-29T19:03:14-05:00, `28.0.2-18-g8c1075228f`) |
| master HEAD | `97f4dadd06a08a478cc702bc55353d2da59ca267` (2026-09-30T17:25:47Z) |
| stable/2026.2 HEAD | `7121bf42621e8f2860100b3bb0e7e9089c007959` (`29.0.0-5`) |

Hagistack evidence read (supporting only): the OVN maintenance lock
investigation, the Rocky backport acceptance, RPM provenance remediation,
runtime evidence remediation, the final focused recheck, and the Ubuntu
reassessment. Facts taken from them: failure mechanism and 4/66 natural rate on
Ubuntu, persistence up to 35.7 min untouched, the `bba77b6ece` hazard, the pair
on Rocky (42 patched starts, 0 affected, RPC workers 0 lock messages, handover
correct). They are causal support, not Ubuntu acceptance.

`ROCKY F-NEW-1 ROOT FIX: CLOSED`

`HAGISTACK PRODUCT MUTATIONS: ZERO`

## B. Current stable status [FRESH]

Searched the whole history of `origin/stable/2026.1`:

| Key | Hits |
|---|---|
| Change-Ids `Iaefe1e2c…`, `I74145ef1…`, `I80e74a39…` | 0, 0, 0 |
| SHAs `83f1d830`, `91abb5e7`, `c695003d` | 0, 0, 0; none is an ancestor of the branch |
| bug numbers `2155155`, `2156979` | 0, 0 |

Source content on the base: `maintenance.py:235` `self._idl.set_lock(MAINTENANCE_NB_IDL_LOCK_NAME)`,
`has_lock` = `not self._idl.is_lock_contended`; `impl_idl_ovn.py` and `mech_driver.py` have no `set_lock` or
`lock_name`. Raw: `preflight/stable-2026.1-presence-check.txt`.

`STABLE/2026.1 MINIMAL ROOT FIX PRESENT BEFORE BACKPORT: NO`

## C. Upstream commit identity [FRESH]

| | `83f1d830…` | `91abb5e7…` |
|---|---|---|
| full SHA | `83f1d8305651a0ab23629c88d70bfa237055158c` | `91abb5e720e1c515dbfbe9b2313fbdff92b2abbf` |
| author | Terry Wilson, 2026-06-09T17:33:16-05:00 | Terry Wilson, 2026-06-17T18:45:25-05:00 |
| committer date | 2026-06-10T01:46:53Z | 2026-06-17T18:45:25-05:00 |
| subject | Ensure MaintenanceWorker lock set before connect | Only set the maintenance worker lock on the worker |
| Change-Id | `Iaefe1e2cc86ddd55c9053fde66353b2a333e1e98` | `I74145ef1407856b7ec75de87daa2270b452b6c70` |
| bug | Related-Bug #2155155 | Closes-Bug #2156979 |
| parent | `c695003d1012b911aa7c3f604d6d169d2567521c` | `319761f0697026227aa7b0a882bfdfddbae74f91` |
| tree | `aa795a7b61bb8e986454e92b0a319cd26db97e47` | `657e22bdefc7ea3cba3ab007e395c6fcb303f522` |
| files | `common/ovn/constants.py` +1, `impl_idl_ovn.py` +1, `maintenance.py` −3 | `mech_driver.py` +3, `impl_idl_ovn.py` +4/−1 |
| contained in | origin/master, origin/stable/2026.2; tags 29.0.0, 29.0.0.0b1, 0rc1, 0rc2 | same |

SHAs, authors, Change-Ids, bug lines and file lists are unchanged from the
September research. Tests added or changed by either commit: none. Full diffs:
`upstream/83f1d830.full.patch`, `upstream/91abb5e7.full.patch`.

`UPSTREAM FIX COMMIT IDENTITIES: VERIFIED`

## D. Minimal fix analysis [FRESH, stable/2026.1 at 8c1075228f]

Worker/startup path traced in the stable tree (`preflight/stable-2026.1-worker-hierarchy.txt`):

- `MaintenanceWorker.start()` → neutron-lib `BaseWorker.start()` → triggers
  `OVNMechanismDriver.post_fork_initialize`; `should_post_fork_initialize`
  accepts `wsgi.WorkerService`, `MaintenanceWorker`, `service.RpcWorker`.
- `post_fork_initialize` → `impl_idl_ovn.get_ovn_idls(self, trigger)` →
  `OvsdbNbOvnIdl.from_worker(trigger_class, driver)` → `ovsdbapp Connection(...)`
  (`Connection.start()` in the constructor path) → `DBInconsistenciesPeriodics.__init__`
  later, after the NB/SB sync (base: calls `set_lock`).
- `from_worker` branches on `worker_class in (worker.MaintenanceWorker, n_service.RpcWorker)` for both NB and SB
  (the `RpcWorker` entry comes from `bba77b6ece`, 2026-06-30, present on stable/2026.1 only).
- Other callers of `from_worker(MaintenanceWorker)` without `post_fork_initialize`:
  `neutron/cmd/ovn/neutron_ovn_db_sync_util.py:266-274`, `neutron/cmd/upgrade_checks/checks.py:213-215`.
- `lock_name`: defined nowhere in Neutron; neutron-lib 3.24.0 `BaseWorker` has no lock attribute
  (checked in the test venv); `RpcWorker` derives from `NeutronBaseWorker`.
- `ovs_fixes.apply_ovs_fixes()` (python-ovs monkeypatch in `post_fork_initialize`) touches `_substitute_uuids` only, not the lock code.

Nothing on the branch has changed enough to alter the conclusion.

`MINIMAL SAFE STABLE/2026.1 FIX: 83f1d830 + 91abb5e7`

## E. Change-1-only hazard [FRESH]

Source: on the base, Change 1 puts `idl_.set_lock(ovn_const.MAINTENANCE_NB_IDL_LOCK_NAME)` inside the shared
`RpcWorker`/`MaintenanceWorker` branch (visible in `patches/range-diff-change1.txt`), with no guard. Every RPC
worker, and every direct `from_worker(MaintenanceWorker)` caller, therefore requests the lock.

Runtime (real `post_fork_initialize`, `from_worker`, `DBInconsistenciesPeriodics`; fresh interpreter each;
raw `evidence/regression/`):

| Scenario | stable/2026.1 | Change 1 only | Change 1 + 2 |
|---|---|---|---|
| RPC worker started: `lock` requests seen by server | 0 | **1** (`idl.lock_name` set) | 0 |
| `from_worker(MaintenanceWorker)` without `post_fork_initialize` (sync-util / upgrade check): lock requests | 0 | **1** | 0 |
| RPC worker started first, then maintenance worker: server lock held after RPC start | no | **yes** | no |
| … maintenance worker state / write | owns lock, write OK | **`is_lock_contended=True`, write fails NOT_LOCKED** | owns lock, write OK |

Scope: this is the ordering hazard, demonstrated with an RPC worker that happens to start first; it is
not claimed that production ordering always lets an RPC worker win.

`83f1d830 ALONE ON stable/2026.1: UNSAFE`

## F. Local backport series

| | SHA |
|---|---|
| base (origin/stable/2026.1) | `8c1075228f41a95351567be57f5bfb3ff8146ed2` |
| Change 1 (from `83f1d830`) | `46256f84578d62e04e45f7d838c850aa518bc2e5` |
| Change 2 (from `91abb5e7`) | `91bb432c5c34acc76edfb597fd0d2fd11afcbc56` |

Branch `fnew1-2026.1-series` in the disposable checkout; also `patches/fnew1-2026.1-series.bundle`.
Base..HEAD: 2 commits, 0 merge commits, 4 files, +8/−3. Author and author date are preserved
(Terry Wilson). The committer is a placeholder (`F-NEW-1 backport prep (local, not a submitter identity)
<noreply@invalid>`): a real submitter must re-commit under their own identity. The original
`Signed-off-by` lines are kept. Reference commits with unmodified messages (same trees):
`4bdb9dc96e…`, `334911737a…`.

`LOCAL SERIES COMMITS: 2`

## G. Diff and range-diff [FRESH]

| Commit | Classification | Evidence |
|---|---|---|
| Change 1 | **EXACT CHERRY-PICK** (no conflict, no fuzz, changed lines identical); commit message extended | `git diff -U0` +/− lines identical (`patches/changed-lines-*-change1.txt`); `range-diff-change1.txt` |
| Change 2 | **EXACT CHERRY-PICK** (same) | `changed-lines-*-change2.txt`; `range-diff-change2.txt` |

`git patch-id` differs from upstream for both (`d4f005b5…` vs `c933e07b…`, `69cb7daa…` vs `b5174f2c…`): the
**context** lines differ. Where: the stable tree's `if worker_class in (worker.MaintenanceWorker, n_service.RpcWorker):`
replaces master's pre-`bba77b6ece` condition and the `args = …` line, visible in the range-diff. No changed line is
adapted.

Combined check: the final `OvsdbNbOvnIdl.from_worker` body equals stable/2026.2's; the `post_fork_initialize`
`lock_name` block equals stable/2026.2's; `maintenance.py` no longer contains `set_lock`; the constant line is
equal. Combined changed lines: `+MAINTENANCE_NB_IDL_LOCK_NAME = …` (constants), `+ lock_name` block (mech driver),
`+ try: idl_.set_lock(worker_class.lock_name) / except AttributeError: pass` (`impl_idl_ovn.py`),
`− # TODO…`, `− MAINTENANCE_NB_IDL_LOCK_NAME = …`, `− self._idl.set_lock(…)` (`maintenance.py`).

`BACKPORT SEMANTIC DELTA FROM UPSTREAM FIX: ZERO`

## H. Exclusions

- `c695003d` and `a8feb94e` are not ancestors of the series; no commit message mentions `c695003d`, `I80e74a39` or
  `a8feb94e`; `has_lock` is still `not self._idl.is_lock_contended`; no changed file under
  `commands.py`, `ovn_client.py` or `bgp/`.
- `c695003d` conflicts on stable/2026.1 in `neutron/services/bgp/reconciler.py`; not resolved, not needed.

`c695003d INCLUDED: NO`

`TAG_REQUEST FIX INCLUDED: NO`

## I. Tests

Environment: macOS 26 (Darwin 25.6.0) arm64, Python 3.12.14, venv created by `tox -e py3` with the
2026.1 upper-constraints (`upper-constraints-2026.1.txt`, SHA-256 `34b8cdec…e7`), neutron-lib 3.24.0, python-ovs 3.7.0,
ovsdbapp 2.16.1, stestr 4.2.1, 8 cores. The python-ovs `idl.py` and ovsdbapp `connection.py` in that venv are
byte-identical to Ubuntu's 3.7.1 and 2.16.0 (zero diff lines, `evidence/*-vs-ubuntu-*.diff`). Tox invokes
`bash {toxinidir}/tools/pip_install_src_modules.sh` first, a no-op without `TOX_ENV_SRC_MODULES`, which
cannot run from a path containing a space, so `stestr run <filters>` was run directly in the tox-created
environment (`tests/run_unit.sh`). Per-run `command.txt`, `stestr-output.txt`, `results.subunit` are in
`evidence/unit/`.

Targeted set: `neutron.tests.unit.plugins.ml2.drivers.ovn`, `neutron.tests.unit.test_service`,
`neutron.tests.unit.conf.test_service`, `neutron.tests.unit.cmd`.

| Run | Tree | Ran | Passed | Skipped | Failed | exit | wall |
|---|---|---|---|---|---|---|---|
| A | stable/2026.1 (`8c1075228f`) | 1049 | 1046 | 3 | 0 | 0 | 47 s |
| B | Change 1 only (`4bdb9dc96e`) | 1049 | 1046 | 3 | 0 | 0 | 52 s |
| C | series tree (`334911737a`, = `91bb432c5c` tree) | 1049 | 1046 | 3 | 0 | 0 | 65 s |

The same 3 tests are skipped on all trees: `AgentCacheTestCase.test_update_while_iterating_agents` (eventlet-removal
skip), `TestOVNMechanismDriverNetworksV2.test_create_port_obj_bulk`, `…SubnetsV2.test_list_subnets_filtering_by_unknown_filter`.

Full unit suite (`neutron.tests.unit`), no other filter:

| Run | Tree | Ran | Passed | Skipped | Failed | exit | wall |
|---|---|---|---|---|---|---|---|
| D | stable/2026.1 | 21220 | 19471 | 1745 | **4** | 1 | 762 s |
| E | series tree | 21220 | 19465 | 1745 | **10** | 1 | 815 s |

Failing tests:
- on both trees (platform): `agent.linux.test_conntrackd…test_build_config`, `agent.linux.test_tc_lib…test_list_tc_policy_classes`,
  `…TcTestCase.test_list_tc_qdiscs_tbf`;
- `extensions.test_segment.TestNovaSegmentNotifier`: 1 test on D, 7 on E. The runs were made while another
  workload had the machine at load 80–120. **Classified: pre-existing flaky, unrelated.** Re-running only
  `neutron.tests.unit.extensions.test_segment` without load: base failed 3, 8, 2 tests, Change 1 only 6, the
  series 2, 5, 4, every time in that one class (`MismatchError: 1536 != 24000`, `TypeError: 'Mock' object cannot be
  interpreted as an integer`). A failing set that varies from 2 to 8 on the unmodified base is not introduced by
  the patch. Nothing in the touched code is imported by that class.

No baseline failure was hidden and no failure was introduced by the series.

## J. Deterministic regression [FRESH]

**Harness** (`tests/fnew1_harness.py`, `tests/stub_ovsdb_server.py`, `tests/run_matrix.py`): real Neutron
classes from the tree under test, python-ovs 3.7.0, ovsdbapp 2.16.1. It runs the real
`OVNMechanismDriver.post_fork_initialize()` for a real `MaintenanceWorker`/`RpcWorker` instance (plugin, agent
cache and synchronizers mocked), which runs the real `get_ovn_idls` → `from_worker` → `Connection.start()`, then
the real `DBInconsistenciesPeriodics.__init__` and a real NB write via `db_set(...).execute(check_error=True)`.
One fresh interpreter per start. The peer is an OVSDB protocol stub (`get_schema`/`list_dbs` with the real OVN
26.03.0 schemas, `_Server` database, `monitor_cond`, RFC 7047 `lock`/`unlock`/`assert`), see §V. "Widened"
holds the gap between "`lock` request sent" and "request id recorded" open until the stub has replied and the
reply bytes have been read (1 s cap), which is exactly the F-NEW-1 interleaving whenever a second thread is
driving the IDL. No external lock waiter is used in any case.

| Tree | widened: stuck / starts | widened: writes OK | unmodified: stuck / starts | lock requests / start |
|---|---|---|---|---|
| stable/2026.1 | **10 / 10** | **0 / 10** (10 NOT_LOCKED) | 0 / 10 | 1 |
| Change 1 only | 0 / 10 | 10 / 10 | 0 / 10 | 1 |
| Change 1 + 2 | **0 / 10** | **10 / 10** | 0 / 10 | 1 |

Signature on every stuck start, recorded per start in `evidence/regression/*.jsonl`: server lock request
received and `{"locked": true}` sent to that session (`server_granted_to_requester=true`), client
`idl.has_lock=False`, `idl.is_lock_contended=False`, `_lock_request_id` still set, Neutron `has_lock=True`, write
fails with "IDL has been configured to require a database lock but didn't get it yet". Patched starts:
`has_lock=True`, `_lock_request_id=None`, write OK.

Two notes on the harness history: an earlier 20 ms sleep version reproduced 7/10 (and alternated between
consecutive in-process starts), so the wait was made conditional on the server reply and reply consumption, and each
start moved to its own interpreter. Natural rate is not reproduced by this harness in either tree (0/10), as in
the September harness, so natural-rate equivalence is argued from the mechanism; the real-server natural rate is
[PRIOR] 4/66.

`DETERMINISTIC F-NEW-1 REGRESSION: PASS`

## K. RPC safety (final series) [FRESH]

- Maintenance worker: `maint_start` 10/10 widened and 10/10 unmodified starts produced exactly 1 `lock` request,
  granted, with `idl.has_lock=True`.
- RPC worker (`rpc_start`): 0 `lock` requests, `idl.lock_name=None`.
- Direct `from_worker(MaintenanceWorker)` (sync-util / upgrade-check shape): 0 lock requests.
- RPC first, then maintenance worker: maintenance worker owns the lock, write OK.

`FINAL SERIES MAINTENANCE WORKER LOCK REQUEST: YES`

`FINAL SERIES RPC WORKER LOCK REQUEST: NO`

## L. Handover sanity [FRESH, supporting]

`handover` scenario, two maintenance workers on the stub: A owns (write OK), B `is_lock_contended=True` and
its write fails NOT_LOCKED; A's connection stops; B receives `locked`, `idl.has_lock=True`, write OK, server
owner = B's session. Same result on stable/2026.1, Change 1 only and the series, as expected: handover is
unchanged by the series. Supporting only; the 32-start and handover campaigns on Rocky remain the downstream
acceptance [PRIOR].

## M. Broader relevant tests and checks

- Full unit suite: §I (runs D, E).
- `flake8` with the repository's `tox.ini` configuration (hacking 8.0.0, neutron local checks, `select = H,N`) on
  the four touched files: exit 0 on the series tree and on the base (`evidence/flake8-*.txt`).
- Not run: the complete `tox -e pep8` environment; functional and fullstack jobs (need Linux, OVS/OVN, privileges:
  §V); `tox -e docs`; release-note check (neither master commit carries a release note, `reno` not needed).
- Commit messages: `evidence/commit-message-check.txt`: subjects 48 and 50 characters (≤ 50), no trailing
  period, blank line after the subject, body ≤ 72 columns, exactly one `Change-Id: I<40 hex>`, bug trailers
  `Related-Bug: #2155155` / `Closes-Bug: #2156979`, `(cherry picked from commit <sha>)` as the last line.

## N. Stable policy

Facts (`evidence/stable-policy-references.md`): project-team-guide/stable-branches: a backport must already be
merged on master and all newer stable branches (here master and stable/2026.2, yes); `git cherry-pick -x`
(done); keep the original Change-Id (done); two stable-maintainer +2 (future); bug fixes are in scope in the
Maintained phase; new features, API, DB-schema and config changes are forbidden (none here). releases.openstack.org:
2026.1 is "Maintained", unmaintained date estimated 2027-10-27. Scope: four files, +8/−3, no API, schema, config
or release note. Regression risk: changes *when* the maintenance lock is requested (at connect instead of after
sync) and adds a class attribute set in `post_fork_initialize`; exercised by the matrix above and by the
unmodified 1049-test set.

Open points (not blockers): bug tasks exist only for the master series (§O), so a 2026.1 series task must be
added by a person with bug rights; stable/2025.2 and stable/2025.1 contain the same `set_lock` in
`DBInconsistenciesPeriodics.__init__` and the same shared `from_worker` branch, so the stable policy would
also apply there after 2026.1 (not assessed, not prepared); stable-maintainer acceptance is not established.

`STABLE POLICY ELIGIBILITY: YES`

(per the written policy only; reviewer acceptance is not predicted.)

## O. Commit messages and bug references

Bug records, re-queried 2026-09-30T22:16Z: #2155155 (Medium) and #2156979 (High), each one task
(`neutron`, Fix Released 2026-06-10 / 2026-06-18), last updated 2026-07-16, no stable series task, no Ubuntu task.
The trailers are the original ones (`Related-Bug: #2155155`, `Closes-Bug: #2156979`); no bug relationship was
invented and no Launchpad task was created.

**Change 1** (`46256f8457…`):

```
Ensure MaintenanceWorker lock set before connect

The Idl.set_lock() call sets the lock name on the Idl class and
sends a request to ovsdb-server requesting a lock. It does not
wait for a reply. This creates a window where we run without
yet receiving the lock, and tasks might fire and fail and have
to be retried.

If set_lock() is called prior to connection, the reply that
contains the initial database dump wil aslo have the reply to the
set_lock request, so we eliminate that window.

Stable backport note: this change must not be merged without its
companion, Change-Id I74145ef1407856b7ec75de87daa2270b452b6c70
("Only set the maintenance worker lock on the worker"), which is
the next change in this series. On stable/2026.1 the RpcWorker
shares the BaseOvnIdl branch of from_worker() (since "rpc/ovn: Use
base OVN IDL for RPC workers"), so this change alone would make
every RPC worker request the maintenance lock.

Why this is a bug fix for stable/2026.1, beyond the window described
above: with Neutron 28.0.2 and python-ovs 3.7.x the lock reply can be
processed by the ovsdbapp connection thread after python-ovs has
sent the "lock" request but before it has recorded the request ID.
The reply is then dropped. ovsdb-server considers the maintenance
session the lock owner, the client does not, and every guarded
write fails with NOT_LOCKED. In downstream testing an affected
worker stayed in this state for the whole untouched observation
windows (longest 35.7 minutes) and recovered when a separate lock
waiter made the server re-notify the owner. Requesting the lock
before the connection thread starts removes the race.

Related-Bug: #2155155
Change-Id: Iaefe1e2cc86ddd55c9053fde66353b2a333e1e98
Signed-off-by: Terry Wilson <twilson@redhat.com>
(cherry picked from commit 83f1d8305651a0ab23629c88d70bfa237055158c)
```

**Change 2** (`91bb432c5c…`):

```
Only set the maintenance worker lock on the worker

Other code passes the MaintenanceWorker as the trigger to
from_server() like the ovn-db-sync-util and only the real
MaintenanceWorker itself should call set_lock() before
connecting.

Stable backport note: this change is required by the previous
change in this series, Change-Id
Iaefe1e2cc86ddd55c9053fde66353b2a333e1e98 ("Ensure
MaintenanceWorker lock set before connect"), and the two must be
merged together. On stable/2026.1 the RpcWorker uses the same
BaseOvnIdl branch of from_worker() as the MaintenanceWorker, so
without this change every RPC worker would request the
maintenance lock. With it, only a worker class that has had
lock_name set in post_fork_initialize() requests the lock, which
is the real MaintenanceWorker.

Closes-Bug: #2156979

Signed-off-by: Terry Wilson <twilson@redhat.com>
Change-Id: I74145ef1407856b7ec75de87daa2270b452b6c70
(cherry picked from commit 91abb5e720e1c515dbfbe9b2313fbdff92b2abbf)
```

Original upstream wording is unmodified; the added paragraphs are separate and labelled. The observation is scoped to
the tested stack ("Neutron 28.0.2 and python-ovs 3.7.x"), says "an affected worker", not all deployments, and is
not described as permanent.

**Dependency and merge strategy.** The two changes are a parent/child stack (Change 2's git parent is Change 1), so
Gerrit cannot submit Change 2 without Change 1. The hazard is Change 1 merging alone. Proposed handling, none of it
executed and the Gerrit/Zuul enforcement not verified (the Zuul documentation reviewed does not describe
git-parent enqueue behaviour):
1. push both as one stack with one topic;
2. the warning is in Change 1's commit message and should be repeated as the first review comment on both;
3. ask reviewers to give Workflow +1 on Change 1 only once Change 2 has its Code-Review votes, and
   optionally hold Change 1 at Workflow −1 (owner) until then;
4. if reviewers prefer, squash the pair into one change (the same four-file diff, message combining the two).
The safety net is that Change 2 on its own does not apply (`91abb5e7` alone conflicts in `impl_idl_ovn.py` on
stable/2026.1).

`CHANGE 1 STANDALONE MERGE: MUST NOT OCCUR`

`CHANGE 2 RESTORES WORKER-SCOPE SAFETY: YES`

## P. Reviewer-facing justification

Full text: `package/patches/REVIEWER_JUSTIFICATION.md`. Sections: 1 what breaks, 2 why it happens, 3 why Change 1
fixes it, 4 why Change 2 must accompany it (with the table of §E), 5 why `c695003d` is excluded (defensive, not
the ordering fix; on its own it would turn the stuck state into silent skipping; BGP conflict; `a8feb94e` unrelated),
6 test evidence (§I, §J), 7 observed impact in the allowed scoped wording:

> "In downstream validation using Neutron 28.0.2 with python-ovs 3.7.1, the affected maintenance worker remained in
> the inconsistent lock state for the full untouched observation windows, including a 35.7-minute run, and
> recovered immediately when a separate lock waiter caused the server to re-notify the owner."

8 downstream: Ubuntu 26.04 ships `2:28.0.2-0ubuntu1`; Hagistack is named only as the source of the reproduction
evidence, not as an obligation on upstream.

## Q. Ubuntu development package [FRESH]

Ubuntu stonking (26.10 development series) `neutron 2:29.0.0~rc1-0ubuntu1`, Release pocket, published
2026-09-16T13:55:18Z. Downloaded and unpacked: `.dsc` `725ae0be…`, `orig.tar.gz` `368eb37d…`, `debian.tar.xz`
`e8ee99b4…`. Ubuntu's only patch is `install-missing-files.patch` (MANIFEST.in). Source inspection (not the
tag inference): `impl_idl_ovn.py:251` `idl_.set_lock(worker_class.lock_name)`; `mech_driver.py:415`
`worker_class.lock_name = ovn_const.MAINTENANCE_NB_IDL_LOCK_NAME`; `constants.py:300` the constant; `maintenance.py`
has no `set_lock`; `has_lock` returns `self._idl.has_lock` (so `c695003d` is present too). SHA-256 prefixes of
all four files equal upstream tag `29.0.0.0rc1`. Record: `evidence/ubuntu-stonking-inspection.txt`. This does not
change the backport; it satisfies the "fix must be in the development release" SRU prerequisite later.

`UBUNTU DEVELOPMENT PACKAGE CONTAINS ROOT FIX: YES`

## R. Evidence

| | |
|---|---|
| directory | `/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-neutron-stable-backport-prep-2026-10-01/package/` |
| files | 231 (+ `SHA256SUMS`) |
| `SHA256SUMS` SHA-256 | `f0fe75c46273219c6393c4317e56fa2f27d9af85f3f5887cd9bda1d913d952d8` |
| repository | `…/neutron/` (branches `fnew1-2026.1-series`, `fnew1-pure-1`, `fnew1-pure-2`; worktrees `wt/base`, `wt/c1`, `wt/final`) |
| secrets | none stored; scanned for private keys, `AKIA…`, `password=` assignments |

Cleanup: the abandoned native OVS build (`ovsbuild`) and the uv download cache were removed; everything else is
kept for the auditor.

## S. Deferred

`c695003d: DEFERRED / SEPARATE`

`TAG_REQUEST: DEFERRED / SEPARATE`

`F13b: DEFERRED`

`CLIFF: DEFERRED`

`O-A: DEFERRED`

`UBUNTU SRU: NOT FILED`

## T. Mutation summary

- Hagistack: product files, tests, docs, spec patches, manifests, earlier evidence: **0** changed (HEAD
  `2077950…` unchanged; nothing staged). One new untracked file: this report.
- Upstream: no push, no `git review`, no Gerrit change, no Launchpad edit or task, no contact with maintainers;
  remote access was fetch/read only.
- Ubuntu: no package built, no SRU, no bug task, no `proposed`.
- Cloud: no GCE resource touched (the instance list was read once, read-only); no VM or container started.
- Local changes outside the repo: a symlink `/private/tmp/hgnp` → the evidence directory (the test scripts need a
  path without a space), and a `uv tool` install of `tox` (tool directory under the evidence directory). No Hagistack
  repository files involved.

`HAGISTACK PRODUCT MUTATIONS: ZERO`

`UPSTREAM REMOTE MUTATIONS: ZERO`

## U. Readiness

### Limitations the independent auditor should weigh

1. **Stub peer.** The deterministic regression ran against an OVSDB protocol stub, not ovsdb-server. The race is
   inside python-ovs/ovsdbapp/Neutron (the server's reply is asynchronous and fast either way), and the stub
   reproduced the real failure signature, but real-server re-runs on the stable/2026.1 head were not made. Real-server
   evidence is [PRIOR] and on 28.0.2 (Ubuntu VM: 5/5 stuck unpatched, 0/5 patched; Rocky: 42 patched starts, 0 affected).
   A native `ovsdb-server` could not be built on macOS (`lib/odp-netlink.h` is Linux-only) and GCE use is not authorised
   by this task; Docker was not running. A real-server run on a Linux host would need infrastructure authorisation.
2. **Upstream gate not run.** Functional, fullstack and docs jobs, and the complete `pep8` environment, were not run;
   Python 3.12 on macOS only. The same two commits already pass the master gate.
3. **Platform failures.** The full unit suite has 3 platform failures and a flaky class on the unmodified base (§I).
4. **Approval and scope.** Stable-maintainer acceptance, Gerrit/Zuul enforcement of the pair, and
   stable/2025.x are not established.

These do not make a required property unknown: each required property in the readiness standard is established
(base verified, fix absent, identities verified, pair dependency understood, both changes prepared, no unrelated
code, semantic equivalence, Change-1 hazard shown, final RPC safety shown, deterministic regression passes,
unit results classified, message conventions met, policy eligible, scoped wording, exclusions, no submission).

STABLE/2026.1 F-NEW-1 BACKPORT: SUBMIT READY / DO NOT SUBMIT

A separate independent audit of the exact local commits and the package must precede any submission. No
submission is authorised by this report.

---

ROCKY F-NEW-1 ROOT FIX: CLOSED
MINIMAL SAFE STABLE/2026.1 FIX: 83f1d830 + 91abb5e7
CHANGE 1 STANDALONE MERGE: MUST NOT OCCUR
DETERMINISTIC F-NEW-1 REGRESSION: PASS
FINAL SERIES RPC WORKER LOCK REQUEST: NO
STABLE POLICY ELIGIBILITY: YES
UBUNTU SRU: NOT FILED
HAGISTACK PRODUCT MUTATIONS: ZERO
UPSTREAM REMOTE MUTATIONS: ZERO
STABLE/2026.1 F-NEW-1 BACKPORT: SUBMIT READY / DO NOT SUBMIT
UBUNTU WP-A STATUS: HOLD
WP-A MERGE: HOLD
