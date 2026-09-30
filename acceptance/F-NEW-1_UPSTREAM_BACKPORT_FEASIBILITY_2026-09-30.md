# F-NEW-1: upstream fix and backport feasibility

Read-only research, 2026-09-30. Candidate `cb3154a` and evidence commit
`2556d83` unchanged. **Untracked by design.** Source checkouts, patched trees
and harness output are in
`/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-backport-2026-09-30/`.

---

## Conclusions

- The upstream fix is **three merged master commits**, all in `stable/2026.2`
  and the 29.0.0 pre-releases, and **none in `stable/2026.1`**. No backport is
  proposed in Gerrit.
- The race is removed by **`83f1d830` together with `91abb5e7`**. `83f1d830`
  alone is **unsafe on 2026.1**: there it would make RPC workers take the
  maintenance lock. `c695003d` (the `has_lock` meaning) is defensive and not
  required. On its own it would turn F-NEW-1 into a silent no-maintenance state.
- The pair applies **cleanly** to the Ubuntu source and to Hagistack's Rocky
  source. Both are the same upstream 28.0.2 tarball; Ubuntu's three patches
  touch other files. The dependencies on both distros already have the
  behaviour the fix relies on.
- On a disposable host, **real Neutron 28.0.2 classes**: unpatched 5/5 stuck
  and 5/5 NB writes refused under the widened race window; patched 0/5 stuck,
  5/5 writes succeed, RPC workers take no lock, and lock handover between two
  workers is correct.
- **Rocky** can carry the pair inside the existing build model. **Ubuntu**
  has no fixed package and none pending. A root fix there means waiting for
  upstream and Ubuntu, or Hagistack owning an Ubuntu Neutron package.

---

## A. Preflight

| | |
|---|---|
| branch / HEAD | `fix/neutron-workers` / `2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f` (parent `cb3154a361f343b940fffaa6bdbc0f5a7aad234e`) |
| origin/master | `7a20dbe1ba8cde14f9e35252e1f9074387d695d6` |
| five WP-A product paths vs cb3154a | 0-byte diff (worktree and HEAD) |
| staged | none |
| untracked | `AGENTS.md` (harness symlink), `acceptance/F-NEW-1_OVN_MAINTENANCE_LOCK_INVESTIGATION_2026-09-30.md`, and this file |

## B. Exact upstream fix

Repository `https://opendev.org/openstack/neutron`, full clone, master at
`7b4e8b73427d82537f7c90e0fa1b4fe5831ac41c` (2026-09-30).

| Commit | Author, date | Subject | Parent | Files | Bug / review |
|---|---|---|---|---|---|
| `c695003d1012b911aa7c3f604d6d169d2567521c` | Rodolfo Alonso Hernandez, 2026-06-03 (merged 06-10) | Use idl.has_lock instead of idl.is_lock_contended for OVSDB lock checks | `592609d08b26` | `maintenance.py` (1 line), `services/bgp/reconciler.py` (1 line), functional `test_maintenance.py`, release note `fix-ovn-lock-check-is-lock-contended-c52bee5f582babad.yaml` | Closes-Bug **#2155155**; Gerrit 991346; Change-Id `I80e74a399b7c3420baf49e0cbc50ddfee0a070e0` |
| `83f1d8305651a0ab23629c88d70bfa237055158c` | Terry Wilson, 2026-06-09 (merged 06-10) | Ensure MaintenanceWorker lock set before connect | `c695003d1012` | `common/ovn/constants.py` (+1), `ovsdb/impl_idl_ovn.py` (+1), `ovsdb/maintenance.py` (−3) | Related-Bug #2155155; Gerrit 992569; Change-Id `Iaefe1e2cc86ddd55c9053fde66353b2a333e1e98` |
| `91abb5e720e1c515dbfbe9b2313fbdff92b2abbf` | Terry Wilson, 2026-06-17 (merged 06-18) | Only set the maintenance worker lock on the worker | `319761f0697026227aa7b0a882bfdfddbae74f91` | `mech_driver.py` (+3), `ovsdb/impl_idl_ovn.py` (+4/−1) | Closes-Bug **#2156979** (High: "neutron-ovn-db-sync-util repair mode fails with OVSDB lock error after 'Ensure MaintenanceWorker lock set before connect'"); Gerrit 993860; Change-Id `I74145ef1407856b7ec75de87daa2270b452b6c70` |

Launchpad #2155155 "OVN maintenance worker uses is_lock_contended instead of
has_lock to determine DB lock ownership" (Medium, Fix Released) is the
upstream bug for F-NEW-1's lock-state half. A fourth change under the same bug,
"More tag_request fixes" (`a8feb94e`, Related-Bug), touches
`commands.py`/`ovn_client.py` only and is **not** part of this fix (see O-8
below).

The causal diff, as it lands on 28.0.2 (`83f1d830` + `91abb5e7`
cherry-picked onto tag `28.0.2`; exported as
`backport-A-lock-before-connect.diff`, SHA-256 `8f8c85dcf69a5a02…ce7d`):

```diff
--- a/neutron/common/ovn/constants.py
+++ b/neutron/common/ovn/constants.py
@@ MAINTENANCE_ONE_RUN_TASK_SPACING = 5  # seconds
+MAINTENANCE_NB_IDL_LOCK_NAME = "ovn_db_inconsistencies_periodics"
--- a/neutron/plugins/ml2/drivers/ovn/mech_driver/mech_driver.py
+++ b/neutron/plugins/ml2/drivers/ovn/mech_driver/mech_driver.py
@@ def post_fork_initialize(...)
         if worker_class == wsgi.WorkerService:
             self._setup_hash_ring()
 
+        if worker_class == worker.MaintenanceWorker:
+            worker_class.lock_name = ovn_const.MAINTENANCE_NB_IDL_LOCK_NAME
+
         # Initialize singleton agent cache and keep a copy.
--- a/neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py
+++ b/neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py
@@ class OvsdbNbOvnIdl ... def from_worker(cls, worker_class, driver=None):
         if worker_class in (worker.MaintenanceWorker,
                             n_service.RpcWorker):
             idl_ = ovsdb_monitor.BaseOvnIdl.from_server(*args)
+            try:
+                idl_.set_lock(worker_class.lock_name)
+            except AttributeError:
+                pass
         else:
             idl_ = ovsdb_monitor.OvnNbIdl.from_server(*args, driver=driver)
         conn = connection.Connection(idl_, timeout=cfg.get_ovn_ovsdb_timeout())
--- a/neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py
+++ b/neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py
-# TODO(bpetermann): move MAINTENANCE_NB_IDL_LOCK_NAME to neutron-lib
-MAINTENANCE_NB_IDL_LOCK_NAME = "ovn_db_inconsistencies_periodics"
@@ class DBInconsistenciesPeriodics.__init__
         self._idl = self._nb_idl.idl
-        self._idl.set_lock(MAINTENANCE_NB_IDL_LOCK_NAME)
         super().__init__(ovn_client)
```

4 files, +8/−3. This is exactly master's current text for these lines.

## C. Fix mechanism

**Before (28.0.2):**

1. `post_fork_initialize` → `get_ovn_idls` → `OvsdbNbOvnIdl.from_worker`
   builds the IDL and the ovsdbapp `Connection`. The API constructor starts
   the connection: `Connection.start()` runs `idlutils.wait_for_change()` and
   then **starts the connection thread**, which loops
   `with self.lock: idl.run()`.
2. About 20 s later (after NB/SB sync), `DBInconsistenciesPeriodics.__init__`
   calls `idl.set_lock()` from the **worker's main thread**, without the
   connection lock.
3. python-ovs sends `lock` and records `_lock_request_id` only after the send
   returns. The connection thread can read `{"locked": true}` in that window;
   the reply matches no id and is dropped. This is F-NEW-1.

**After (`83f1d830` + `91abb5e7`):**

1. `post_fork_initialize` marks `MaintenanceWorker.lock_name` before calling
   `get_ovn_idls`.
2. `from_worker` calls `idl_.set_lock(worker_class.lock_name)` **before the
   `Connection` exists**. The session is not connected yet, so python-ovs only
   records `lock_name` and sends nothing (`__do_send_lock_request`:
   `if self._session.is_connected(): … else: msg_id = None`).
3. `Connection.start()` → `wait_for_change()` runs `idl.run()` **in the
   calling thread**. On connect, `run()` itself sends the lock request
   (`if self.lock_name: self.__send_lock_request()`) and processes the reply.
   Only one thread ever touches the lock bookkeeping, both during start and
   afterwards in the connection thread. The request/reply id race cannot
   happen.
4. `DBInconsistenciesPeriodics.__init__` no longer touches the lock.

**Why `91abb5e7` is part of it, not an extra.**
- *Upstream:* `83f1d830` set the lock for every `from_worker(MaintenanceWorker)`
  caller, including `neutron-ovn-db-sync-util` (bug #2156979, High).
- *On 2026.1 specifically:* the later backport "rpc/ovn: Use base OVN IDL for
  RPC workers" (`bba77b6ece` on stable/2026.1, master `e6a0f5afbe`, 2026-06-30)
  puts `RpcWorker` in the same `from_worker` branch. The literal `83f1d830`
  line would make **every RPC worker request the maintenance lock**, verified
  in the cherry-picked tree. That is a new defect: RPC workers could win the
  lock and leave the real maintenance worker permanently contended.
- *How `91abb5e7` guards it:* it keys the call on `worker_class.lock_name`,
  which neither `RpcWorker` nor neutron-lib 3.24 `BaseWorker` defines
  (`AttributeError` → no lock).

**`has_lock` (`c695003d`):**
- *What it corrects:* `not is_lock_contended` is True in the "requested, no
  reply yet" state. With the race removed, that state no longer occurs at
  start: the reply is processed inside `wait_for_change()` before the worker
  continues. It can still occur briefly after an NB reconnect, when the
  connection thread re-requests the lock. In that case the old check lets
  guarded tasks run and fail `NOT_LOCKED` until the reply arrives, which is
  self-healing and not persistent.
- *Classification:* defensive correctness, **not required** to eliminate
  F-NEW-1.
- *On its own it is not a fix.* In the dropped-reply state it would make
  Neutron report no lock, so every guarded task would **skip silently for
  ever**. The worker would stop maintaining without logging anything.

## D. Minimal patch set

**MINIMAL REQUIRED UPSTREAM COMMITS: `83f1d8305651a0ab23629c88d70bfa237055158c` + `91abb5e720e1c515dbfbe9b2313fbdff92b2abbf` (always together)**

`c695003d1012b911aa7c3f604d6d169d2567521c`: recommended as a separate
defensive change, not required. Its `maintenance.py` hunk applies cleanly
to 28.0.2. Its `services/bgp/reconciler.py` hunk conflicts, because master has
extra startup-wait code that 28.0.2 lacks; that hunk is BGP-only and irrelevant
to Hagistack.

Behaviour beyond F-NEW-1:
- The pair changes **when** the maintenance lock is requested (at connect,
  before the initial dump, instead of ~20 s later). It also moves the constant
  to `common/ovn/constants.py`.
- No other process type requests a lock.
- Lock contention and handover between two maintenance workers are unchanged
  (§J).

## E. stable/2026.1 status

| Question | Answer | Reference |
|---|---|---|
| fix in stable/2026.1 | **absent**: no commit with any of the three Change-Ids | `git log --grep=<Change-Id> origin/stable/2026.1` → empty; branch head `1a390f5e27` = `28.0.2-17-g1a390f5e27`, 2026-09-29 |
| fix in stable/2026.2, 29.0.0 pre-releases | present (all three) | same query; `git tag --contains c695003d` → `29.0.0.0b1`, `rc1`, `rc2` |
| pending backport in Gerrit | **none** | `review.opendev.org/changes/?q=change:<id>` → master only (991346, 992569, 993860); `bug:2156979` → 0 changes; no open stable/2026.1 change mentioning the lock |
| tracking bug for backport | #2155155 and #2156979 have a single `neutron` task, Fix Released; no stable series task | Launchpad API |
| policy | 2026.1 is **Maintained** (estimated to become Unmaintained 2027-10-27). Stable policy: a backport must already be on master and all newer stable branches, which is satisfied (master, stable/2026.2); proposed with `git cherry-pick -x` | releases.openstack.org; project-team-guide stable-branches |

## F. Ubuntu 26.04 status

| Question | Answer |
|---|---|
| current package | `neutron 2:28.0.2-0ubuntu1`, resolute-updates, published 2026-09-24 |
| pending | nothing newer in resolute-proposed; the only 28.0.2 proposed upload is this one, already released |
| orig tarball | `neutron_28.0.2.orig.tar.gz` SHA-256 `cdaf45a2…25ee`, **identical to upstream 28.0.2** (downloaded and hashed) |
| Ubuntu patches | `install-missing-files.patch` (MANIFEST.in), `skip-iptest.patch` (an ipset unit test), `lp2150285-keep-mod-wsgi-operational.patch` (`neutron/common/wsgi_utils.py` + test). **None touches** `maintenance.py`, `impl_idl_ovn.py`, `mech_driver.py` or `constants.py`, and none mentions the lock |
| installed code | `maintenance.py` SHA-256 `22baf6d9…f681`, identical to upstream 28.0.2 |
| Launchpad | no Ubuntu `neutron` bug for this (searches: maintenance worker lock, is_lock_contended, 2155155, ovn_db_inconsistencies_periodics; the one `NOT_LOCKED` hit is an unrelated jammy/yoga bug) |
| how Ubuntu ships stable fixes | point-release SRUs under the OpenStack StableReleaseUpdates process; 28.0.2 arrived through LP #2167438 "[SRU] Neutron gazpacho stable releases" (upstream tag 2026-09-10 → resolute-updates 2026-09-24) |

**The Ubuntu 26.04 package does not contain the fix, and no fix is pending.**

## G. Rocky source status

- Hagistack's Rocky input: `neutron-28.0.2.tar.gz` pinned `cdaf45a2…25ee`,
  the same file as Ubuntu's `.orig`. RDO distgit
  `fa1f5135e66282364250f2f5630a48423f497099`.
- The spec declares **no `Patch` lines** and uses
  `%autosetup -n %{service}-%{upstream_version} -S git`, so a declared
  `PatchNNNN` would be applied.
- Hagistack's `spec-patches/neutron.patch` only edits `%files`. In the
  affected code path, Rocky's source equals the plain tarball.

## H. Dependency compatibility

| | Ubuntu 26.04 | Rocky 10.2 (Hagistack build) |
|---|---|---|
| neutron | 2:28.0.2-0ubuntu1 | 1:28.0.2-1.el10 (self-built) |
| ovsdbapp | 2.16.0-2 | 2.16.1-1.el10 (self-built) |
| python-ovs | python3-openvswitch 3.7.1-2 | python3-openvswitch3.5 3.5.3-5.el10s (NFV SIG) |
| OVS / OVN | openvswitch-common 3.7.1-2 / ovn-central 26.03.0-2 | NFV SIG OVS / OVN (as in WP-A) |
| neutron-lib | (distro) | 3.24.0-1.el10 |

The fix relies on:

1. python-ovs deferring the lock request until connected and re-sending it
   from `run()` on connect;
2. ovsdbapp `Connection.start()` running `wait_for_change()` in the caller's
   thread before starting the connection thread.

Both were checked in the exact upstream sources. `ovs/db/idl.py` is identical
in the relevant lines in **v3.5.3 and v3.7.1** (lines 447–448, 818–830).
`ovsdbapp/backend/ovs_idl/connection.py` `start()` is identical in **2.16.0 and
2.16.1**. No newer API, dependency or other Neutron change is needed.

## I. Patch application

`backport-A-lock-before-connect.diff` with `patch -p1`:

| Tree | Clean apply | Fuzz/offset | Other |
|---|---|---|---|
| Ubuntu: upstream tarball + Ubuntu `debian/patches` series applied in order (all 3 applied cleanly first) | **YES** | none | `py_compile` of the 4 files OK; `mech_driver.py` already imports `ovn_const` and `worker`; the moved constant is defined once and referenced once |
| Rocky: upstream tarball (manifest pin) | **YES** | none | same; the patched OVN driver tree is byte-identical to the Ubuntu one |

`git cherry-pick -x` onto tag `28.0.2`:

- `83f1d830`: clean, but **semantically wrong alone** (RPC workers would lock, §C).
- `91abb5e7`: clean.
- `c695003d`: conflict in `services/bgp/reconciler.py` only.

Existing 28.0.2 tests: only functional tests touch the lock (`test_maintenance.py`
releases it with `set_lock(None)`; `test_ovn_db_sync.py` mocks `set_lock`/`has_lock`).
No unit test depends on `set_lock` being called in `DBInconsistenciesPeriodics.__init__`.

**Upstream tests:**
- `83f1d830` and `91abb5e7` add **no tests**.
- `c695003d` only mocks `has_lock=True` in a functional helper.

**No upstream test exercises the race.** Confidence here comes from the
mechanism and the harness below, not from upstream CI.

## J. Disposable validation

One disposable Ubuntu 26.04 VM (`hgfb-1`, n2-standard-2, deleted), archive
packages `python3-neutron 2:28.0.2-0ubuntu1`, `python3-ovsdbapp 2.16.0-2`,
`python3-openvswitch 3.7.1-2`, `ovn-central 26.03.0-2`, NB on
`ptcp:6641:127.0.0.1`.

The harness `neutron_lockfix_check.py` drives the **real Neutron code
path**:

- `OvsdbNbOvnIdl.from_worker(MaintenanceWorker)`, which starts the connection
  thread;
- the real `DBInconsistenciesPeriodics.__init__`, with a mock `ovn_client`
  carrying the real NB API.

UNPATCHED = the installed package. PATCHED = the same 28.0.2 source with the
backport, imported from `/opt/patched`. In patched mode the harness also
reproduces the one line `post_fork_initialize` gains
(`MaintenanceWorker.lock_name = …`). "widen" inserts `sleep(0.02)` in python-ovs
between sending the lock request and recording its id. Each start then does a
real NB write (`NB_Global.external_ids`).

| Mode | Window | Stuck | Lock state | NB writes | RPC worker lock |
|---|---|---|---|---|---|
| UNPATCHED | widen | **5/5** | `has_lock=False is_lock_contended=False _lock_request_id=<id> neutron_has_lock=True` | **5/5 fail `NOT_LOCKED`** | none |
| PATCHED | widen | **0/5** | `has_lock=True _lock_request_id=None` | **5/5 OK** | none |
| UNPATCHED | as is | 0/20 | normal | 20/20 OK | none |
| PATCHED | as is | 0/20 | normal | 20/20 OK | none |
| PATCHED, two workers | as is | — | A `has_lock=True`; B `is_lock_contended=True`, neutron `has_lock=False` (guarded tasks skip); after A stops, B `has_lock=True` | — | — |

The NB DB afterwards holds `external_ids` keys only from the successful
modes (`hgfb-patched-widen`, `hgfb-patched-asis`, `hgfb-unpatched-asis`).

**Scope of this validation.** It proves the patched code path cannot enter
the F-NEW-1 state even when the window is forced open, and that normal start,
lock ownership, writes and handover work. It did **not** run a full patched
Neutron deployment or the natural-rate trials (4/66 unpatched in the
investigation). The minimal harness does not hit the natural window in either
mode, so natural-rate equivalence is argued from the mechanism, not measured.

## K. Root-fix coverage (starts outside a Hagistack run)

The fix lives in the worker's own start-up code, so it applies to **every**
start: first install, reboot, manual `systemctl restart`, package-triggered
restart (postinst `restart` on upgrade) and `Restart=on-failure` crash
recovery. After start, NB reconnects are single-threaded and were never
exposed.

## L. Hagistack Option 2 (health check + restart), analysed, not implemented

| Question | Finding |
|---|---|
| Detection reliable? | Yes, if keyed to the **current** MainPID tree and to lines after that tree's `finished the post initialization`. The stuck state produces `NOT_LOCKED` within 0.1–0.15 s (§G of the investigation) and never clears alone |
| False positives from old entries | Possible if matched by time or whole file (the fresh-install log holds thousands of pre-config ERRORs). Avoidable only by PID-tree filtering |
| Race after the check | The race happens once per process start; a passing check stays valid until the next start |
| Repeated race | about 6 % per start (4/66); 3 attempts ≈ 0.02 % residual, if starts are independent |
| Reboot / manual / package / crash restarts | **Not protected**; Hagistack is not running then |
| Cost to Hagistack | ~25–40 s wait per run, Neutron log parsing, a restart loop: self-healing machinery the project principles avoid |

**Classification: TEMPORARY MITIGATION.** It is a partial mitigation limited
to Hagistack runs, and it is **rejected as a permanent solution**.

## M. Ubuntu packaging boundary

| Option | Scope expansion | Burden | Security/updates | Eliminates race | Protects reboot etc. | Time dependency | Stays "Ubuntu distro packages" | Class |
|---|---|---|---|---|---|---|---|---|
| U1 wait for stable backport + Ubuntu update | none | none | normal | yes | yes | unbounded; nothing proposed yet | yes | ROOT FIX (future) |
| U2 contribute stable backport + request Ubuntu SRU | none in product; external contribution effort | low | normal | yes | yes | stable review + next point release / SRU (28.0.2 took ~2 weeks from tag to -updates) | yes | ROOT FIX (future, accelerated) |
| U3 Hagistack-built Ubuntu Neutron package | **large**: Hagistack becomes an Ubuntu package maintainer (source package, versioning above `0ubuntu1`, repo, signing, security tracking) | high, continuing | Hagistack must track every Ubuntu neutron security update | yes | yes | immediate | **no** | ROOT FIX, **reject** under current principles |
| U4 runtime workaround (Option 2) | small code, new behaviour | medium | none | no (re-rolls) | no | immediate | yes | TEMPORARY MITIGATION |
| U5 hold Ubuntu WP-A until a fixed package exists | none | none | normal | n/a | n/a | = U1/U2 | yes | — |

There is no configuration switch that changes the lock ordering. The race is
in Neutron code, so no narrow supported mechanism short of a patched Neutron
removes it.

**UBUNTU DISTRO-PACKAGE MODEL CAN BE PRESERVED NOW: NO**

That is, not with a root fix today. It can be preserved by waiting (U1/U2),
optionally with U4 as a stated temporary mitigation.

## N. Rocky packaging

Carrying the pair fits the existing model without changing `build-rpms.sh`:

- **Patch location:** `spec-patches/neutron.patch` can add, in the staged
  distgit tree, (a) one `PatchNNNN:` line to `openstack-neutron.spec` and
  (b) the source-patch file itself (a new-file hunk).
- **Staging and application:** `build_one()` copies every non-spec file of the
  staged tree into `SOURCES` (the "every other tracked file … is a
  Source/Patch" loop), and `%autosetup … -S git` applies declared patches in
  order.
- **Readability cost:** a patch that carries a patch. The only alternative
  (a separate source-patch directory) would need a small `build-rpms.sh`
  change.
- **Scope:** the patch changes only the four Neutron files above.
- **Provenance:** tarball SHA-256 and distgit commit are unchanged. The
  `neutron.patch` hash changes. The manifest `release` for neutron should go
  `1` → `2`, so patched RPMs are distinguishable by NEVRA
  (`openstack-neutron-*-1:28.0.2-2.el10`). The WP-A inventory and evidence
  then describe `-1` builds, and a new build and evidence would be needed.
- **Testing:** rebuild, then repeat the F-NEW-1 trial loop on Rocky (expect
  0), plus WP-A Rocky acceptance.

**ROCKY BACKPORT FEASIBLE WITHIN CURRENT MODEL: YES**

## O. Asymmetric options (consequences only)

| Option | Consequences |
|---|---|
| hold WP-A entirely | No regression anywhere. Both distros keep running **no** maintenance worker (F02 stays open) until Ubuntu is fixed; Rocky's also waits without need |
| fix Rocky (carry backport), keep Ubuntu WP-A held | Rocky gets a working worker with the root fix and a new build/evidence cycle. WP-A must be split by distro. Ubuntu stays without a maintenance worker |
| keep both held until Ubuntu fixed | As "hold entirely"; one merge later, one evidence cycle |
| document the upstream defect and merge anyway | Both distros get the worker. About 6 % of worker starts leave it silently useless until a restart, while `active` in systemd and in `hagistack status`. Still strictly more maintenance than today (F02: never). Plus Rocky root fix, if carried |
| remove/disable the worker again | Returns to F02: ML2/OVN under WSGI never runs NB/SB sync or inconsistency repair. Rejected by F02's own finding, not a remedy |

## P. O-A

- **Independent of F-NEW-1.** F-NEW-1 occurs on final configuration and on
  any start. O-A concerns whether a start can use stale configuration.
- **Confirmed by preserved evidence.** In the WP-A fresh run (ubu1), Hagistack
  logged `neutron-rpc-server`, `neutron-periodic-workers` and
  `neutron-ovn-maintenance-worker` as "already running with the current
  configuration" and restarted **only** the metadata agent. Those three final
  starts were systemd `Restart=on-failure` restarts after the config write.
- **The latent gap.** Hagistack's restart decision is a one-second mtime
  comparison. It could keep a process started from a partially written or
  one-file-old configuration.
- **Needs a follow-up WP, not this one.**

**O-A: SEPARATE FOLLOW-UP**

## Q. WP-A evidence correction (for a later separate commit; no edit now)

`acceptance/WP-A_NEUTRON_WORKERS_2026-09-30.md` at `2556d83`:

1. Line 475. Current:
   "…crash with `DBNonExistentTable: …` until Hagistack configures and restarts them. That is the NRestarts count above."
   Proposed:
   "…crash with `DBNonExistentTable: …`, and systemd (`Restart=on-failure`) keeps restarting them; the restart after Hagistack wrote the configuration is the one that stays up. Hagistack itself found these three units already running with the current configuration and restarted only the metadata agent. That is the NRestarts count above."
2. Line 628 (§13 table), current `| ubu1 fresh install | by Hagistack after configuration | no | …`.
   Proposed: `| ubu1 fresh install | by systemd (Restart=on-failure) after Hagistack wrote the configuration | no | …`.
3. Lines 649–653 (§13 "Scope for WP-A"). The rate statement ("0 of 3 starts by
   Hagistack or systemd…") and "It did not appear … when Hagistack itself
   (re)started the worker" are superseded. Proposed: add "Superseded by the
   F-NEW-1 investigation: 4 of 66 starts affected, including plain
   `systemctl restart`; not specific to convergence."

## R. Upstream contribution path

1. **Neutron stable/2026.1:** propose `git cherry-pick -x 83f1d830…` and
   `git cherry-pick -x 91abb5e7…` (clean on the branch, §I), optionally
   `c695003d…` with its BGP hunk resolved, via Gerrit to `stable/2026.1`.
   Reference #2155155 and #2156979, and ask for a 2026.1 series task.
   Reviewers should be told explicitly that `83f1d830` must not merge without
   `91abb5e7` on 2026.1 (RPC-worker context). No new bug is strictly needed;
   a new bug describing the persistent-`NOT_LOCKED` symptom would help
   searchability.
2. **Ubuntu 26.04:** either wait for the next 28.0.x point release
   (point-release SRU like LP #2167438), or open a Launchpad bug on `neutron
   (Ubuntu)` with the SRU template (Impact, Test Plan, Where problems could
   occur), asking for a cherry-pick SRU of the merged stable change.
3. **Evidence already available:** wire captures showing grant then
   client-side `NOT_LOCKED`, trial rates (4/66), the probe mechanism, and the
   deterministic harnesses. The real-Neutron-class harness is suitable as
   reproduction and verification material. As a CI test it would need
   python-ovs internals patched, so it is an illustration, not a regression
   test.

Nothing was submitted.

## S. Impact

| Statement | Status |
|---|---|
| Data corruption | none observed; refused transactions never reach the server, so no partial writes (demonstrated: no NB traffic while stuck) |
| Maintenance reconciliation prevented | **demonstrated**: every NB-writing maintenance task fails for the life of the process |
| Neutron/OVN divergence can persist | **inferred**: any inconsistency the worker would repair stays until restart; no divergence was created to test this |
| Tenant networking | API, RPC server, agents unaffected while stuck (demonstrated for API and units); guest/overlay not re-tested during a stuck window |
| Visible to systemd | **no**: `active/running`, `Result=success` |
| Restart fixes it | **not necessarily**: each start re-rolls the race (about 94 % success) |
| Recurs after reboot | yes in principle: every start is exposed |
| Both distro families | same Neutron code and same python-ovs/ovsdbapp lock code on both (§H); natural occurrence demonstrated on Ubuntu only |

Other finding, not part of F-NEW-1 (**O-8**): the WP-A neutron-api error
`attempting to write bad value to column tag_request` matches upstream "More
tag_request fixes" (`a8feb94e`, master/2026.2). Its prerequisite "Switch from
setting LSP.tag to LSP.tag_request" is in 28.0.2, but the follow-up is not in
stable/2026.1. Recorded only.

## T. Decision matrix

| Option | Ubuntu | Rocky | Root fix? | Protects reboot? | Scope expansion | Dependency | WP-A merge implication |
|---|---|---|---|---|---|---|---|
| 1. upstream stable + Ubuntu update | fixes | fixes only if Hagistack moves its manifest pin to a future 28.0.x that contains it | yes | yes | none | stable review, point release, SRU; nothing proposed yet | Ubuntu WP-A waits |
| 2. Hagistack Rocky backport | — | fixes | yes | yes | small, within model (spec patch + release bump) | none external | Rocky can proceed after rebuild + evidence |
| 3. Hagistack Ubuntu custom package | fixes | — | yes | yes | **large**, contradicts the Ubuntu model | Hagistack package maintenance | would unblock Ubuntu at the cost of the packaging principle |
| 4. restart/detection workaround | mitigates | mitigates | no | no | medium, new self-healing behaviour | none | merge with a known residual defect |
| 5. wait / hold | — | — | n/a | n/a | none | = option 1 | HOLD |

## U. Recommended next action

Narrowest sustainable path consistent with the project principles, in order
(none implemented):

1. **Upstream first (option 1/2):** propose the stable/2026.1 cherry-picks
   of `83f1d830` + `91abb5e7`, and a Launchpad report for Ubuntu. This is the
   only route that fixes Ubuntu without changing Hagistack's packaging model.
2. **Rocky (option 2):** authorise a separate, small WP to carry the same pair
   as a Neutron source patch in the Rocky build (release 1 → 2), then rebuild
   and re-run the Rocky evidence including the F-NEW-1 trial loop.
3. **Ubuntu WP-A:** keep held until a fixed Ubuntu package exists. Merging
   earlier is a product decision: documented known defect, with Option 2 only
   as an explicitly temporary mitigation. Do not build Ubuntu packages (option 3).
4. O-A and the evidence corrections (§Q): separate follow-ups.

## V. WP-A status

No supported fix is available without further product change.

**WP-A MERGE: HOLD**

## W. Mutation summary

- product files modified: 0; tests: 0; docs: 0; spec patches: 0; manifests: 0
- staged: 0; commits: 0; pushes: 0; PRs: 0; tags/releases: 0
- nothing submitted to Gerrit or Launchpad
- one disposable VM created and deleted (§J); cloud state back to the
  2026-09-30T10:02Z baseline

**F-NEW-1 FEASIBILITY RESEARCH MUTATIONS: ZERO**
