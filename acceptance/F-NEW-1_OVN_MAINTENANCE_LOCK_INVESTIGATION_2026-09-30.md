# F-NEW-1 investigation: OVN maintenance worker runs without its lock

Read-only root-cause investigation, 2026-09-30, Ubuntu 26.04 on GCE.
Candidate `cb3154a` (unchanged), evidence commit `2556d83` (unchanged).
**Not committed; untracked by design.** Raw evidence stays outside Git in
`/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-investigation-2026-09-30/`.

---

## Summary

The maintenance worker asks ovsdb-server for the named lock
`ovn_db_inconsistencies_periodics`. The server **grants** it (`{"locked": true}`
on the wire, every time). In about 1 start in 16, the worker **loses the
grant inside its own process** because of a thread race in Neutron 28.0.2's
use of python-ovs:

1. Neutron calls `Idl.set_lock()` from the worker's main thread
   (`DBInconsistenciesPeriodics.__init__`) while ovsdbapp's connection thread
   is already running `Idl.run()` on the same IDL.
2. python-ovs sends the `lock` request first and records its JSON-RPC id
   (`_lock_request_id`) only afterwards. If the connection thread reads the
   reply in between, the reply matches nothing and is dropped (logged at DEBUG
   only).
3. The IDL is left with `has_lock=False`, `is_lock_contended=False`. Neutron
   28.0.2 computes its own `has_lock` as `not is_lock_contended`, so it
   believes it holds the lock and runs every maintenance task. python-ovs
   refuses each transaction client-side (`NOT_LOCKED`), so nothing goes on the
   wire and nothing ever corrects the state.
4. The earlier "read-only probe" healed it because ovsdb-server re-sends a
   `locked` notification to the **current owner** whenever any other waiter on
   that lock disconnects, and python-ovs accepts a `locked` notification
   without an id check.

Hagistack does not cause it and cannot see it. Every start of the worker is
exposed (apt, `systemctl restart`, Hagistack, and by the same code, reboots
and systemd auto-restarts), not only existing-host convergence. Upstream
Neutron master has changed both implicated lines; `stable/2026.1` (the series
Ubuntu ships as 28.0.2) has not.

---

## A. Preflight

| | |
|---|---|
| branch | `fix/neutron-workers` |
| HEAD | `2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f` (evidence commit), parent `cb3154a361f343b940fffaa6bdbc0f5a7aad234e` |
| candidate tree | `a3e16307dfe5bff1500cf9b7056ac8ff304d8a76` |
| origin/master | `7a20dbe1ba8cde14f9e35252e1f9074387d695d6` |
| `git diff cb3154a HEAD` over the five product paths | 0 bytes; `--name-status` shows only `A acceptance/WP-A_NEUTRON_WORKERS_2026-09-30.md` |
| working tree | clean apart from the harness `AGENTS.md` symlink; nothing staged |
| deployed `ubuntu26.04/hagistack` on every host, before every run | `81c4e62685a92f3264051890b518c3dcc3be0710483fe9d86acc83f4b0ed6559`; parent copy `d2d35ad9…` |

## B. Timeline from the earlier WP-A evidence

The earlier run preserved Hagistack run logs, apt history and snapshots, but
**not** `/var/log/neutron`, the journal or ovsdb-server logs (the VMs were
deleted). What can be reconstructed for the real `7a20dbe → cb3154a` host
(hgwpa-ubu3):

| UTC | Event | Source |
|---|---|---|
| 07:16:32 | Neutron config hashes recorded (neutron.conf `65d17813…`, ml2 `4242d108…`) | snapshot |
| 07:17:58–07:17:59 | apt: install maintenance worker, remove neutron-server; postinst starts the unit | apt history |
| 07:17:59 | unit `ActiveEnterTimestamp`, MainPID 27893 | snapshot |
| 07:18:00.636 | `OVN maintenance process starting...` | printed at the time |
| (after) | Hagistack: `neutron configuration already correct (unchanged)`, `neutron-db-manage upgrade`, apache2 reload, `…maintenance-worker already running with the current configuration` | run log (no timestamps) |
| 07:18:22.037 | `Maintenance task thread has started` / post-initialization | printed at the time |
| from 07:18:22 | `NOT_LOCKED` failures (33 961 ERROR lines by 07:24) | printed at the time |
| 07:24:02 | config hashes unchanged from 07:16:32 | snapshot |
| 07:24:17.826 | last ERROR, at the moment of the diagnostic `ovsdb-client lock` probe | printed at the time |

So the affected worker there was started once, by apt, on the **final**
configuration. That already ruled out stale configuration for that case.

## C. Source trace (exact deployed versions)

| Component | Version | How established |
|---|---|---|
| neutron | `2:28.0.2-0ubuntu1` (`python3-neutron` `.deb` SHA-256 `01f53def…`) | `apt-get download` on the test host; `maintenance.py` byte-identical to upstream 28.0.2 (`22baf6d9…`) |
| ovsdbapp | `python3-ovsdbapp 2.16.0-2` (`f51392d6…`) | same |
| python-ovs | `python3-openvswitch 3.7.1-2` (`302fcab8…`) | same |
| ovsdb-server | Open vSwitch 3.7.1 (`ovsdb-server-nb.log`: "ovsdb-server (Open vSwitch) 3.7.1"); source `openvswitch-3.7.1.tar.gz` `b8936c2e…` | log + upstream tarball |
| OVN | `ovn-central 26.03.0-2` | earlier status output |

**The lock is an ovsdb-server named lock**, `ovn_db_inconsistencies_periodics`,
on the maintenance worker's own northbound IDL session. It is not the Neutron
hash ring: only `wsgi.WorkerService` registers in the hash ring
(`mech_driver._setup_hash_ring`), and the maintenance worker never does.

Path, Neutron 28.0.2:

1. `neutron-ovn-maintenance-worker` → `neutron.cmd.server:main_ovn_maintenance`
   → `server.boot_server(ovn_maintenance.ovn_maintenance_worker)` →
   `service.start_ovn_maintenance_worker()` → `MaintenanceWorker.start()`.
2. `OVNMechanismDriver.post_fork_initialize` (worker class `MaintenanceWorker`):
   `impl_idl_ovn.get_ovn_idls()` → `OvsdbNbOvnIdl.from_worker()` builds a
   `BaseOvnIdl` and an ovsdbapp `connection.Connection`, whose thread runs
   `with self.lock: self.idl.run()` in a loop.
3. NB/SB syncs, then `_start_maintenance_thread()` →
   `DBInconsistenciesPeriodics.__init__` → **`self._idl.set_lock(MAINTENANCE_NB_IDL_LOCK_NAME)`**
   from the worker's main thread, without ovsdbapp's `Connection.lock`.
4. `DBInconsistenciesPeriodics.has_lock` = **`not self._idl.is_lock_contended`**;
   `@has_lock_periodic` tasks skip only when that is False.

python-ovs 3.7.1 `ovs/db/idl.py`:

- `set_lock` → `__send_lock_request()`:
  `self._lock_request_id = self.__do_send_lock_request("lock")`. The request
  is sent inside `__do_send_lock_request`, and the id is stored only after it
  returns.
- `Idl.run()` accepts a lock reply only if
  `self._lock_request_id is not None and self._lock_request_id == msg.id`;
  otherwise it logs `received unexpected … message` at **DEBUG**.
- A `locked` notification is accepted by name only (`__parse_lock_notify`),
  with no id check.
- `Transaction.commit()`: `if self.idl.lock_name and not self.idl.has_lock:
  NOT_LOCKED` is decided **client-side**, before anything is sent.
- On reconnect, `run()` re-sends the lock request from the connection thread
  itself (no race there).

ovsdb-server 3.7.1:

- `lock` in WAIT mode (`ovsdb_jsonrpc_session_lock`) creates no victim and
  sends nothing to the owner; only `steal` sends `stolen`.
- `ovsdb_jsonrpc_session_unlock__` (run when any waiter is removed, including
  at disconnect) calls `ovsdb_lock_waiter_remove`, which returns the **current
  owner** whenever waiters remain, and then sends that owner a `locked`
  notification, **whether or not the removed waiter was the owner**.

Neutron's TCP stream class disables OVSDB-level inactivity probes
(`NoProbesMixin`, TCP keepalive instead), so an idle, healthy connection is
never reconnected.

## D. Ubuntu package startup contract

`neutron-ovn-maintenance-worker 2:28.0.2-0ubuntu1`: `Depends: python3-neutron`,
`Conflicts: neutron-server`. `postinst` (debhelper): `update-rc.d … defaults`,
`deb-systemd-helper enable`, then `deb-systemd-invoke start` on first install
(`restart` on upgrade), each `|| true`. The unit: `Type=simple`,
`ExecStart=/etc/init.d/neutron-ovn-maintenance-worker systemd-start`,
`Restart=on-failure`, `After/Wants` mysql, postgresql, rabbitmq-server,
keystone; **nothing about OVN**; empty `TimeoutStartSec=`/`TimeoutStopSec=`
(the source of the parse warnings). No readiness: `start` returns once the
process forks, long before the ~20 s post-fork initialization that takes the
lock. `prerm` stops the unit on removal.

So apt can start the worker at any point during Hagistack's run. It carries
no ordering guarantee. In the investigated failure, however, apt start is
just one way of starting a process that then races internally (§G).

## E. Hagistack convergence order (candidate `phase_neutron`)

1. Per-package check; `apt-get install` of the six real packages if any is
   absent or `neutron-server` is present (postinst starts the units).
2. `ini_set` writes to `neutron.conf`, `ml2_conf.ini`,
   `neutron_ovn_metadata_agent.ini`; ownership `root:neutron`, `0640`.
3. `neutron-db-manage upgrade head`.
4. Keystone user/role/service/endpoints.
5. apache2 ProcSubset drop-in; reload (or restart if the drop-in changed).
6. `service_apply` for each of the four units: restart only if
   `max(stat %Y of the three configs) -gt ExecMainStartTimestamp` (seconds),
   otherwise "already running with the current configuration".
7. API probe, `/proc/meminfo` check.

- **Existing host:** the configs are unchanged and older than the apt start,
  so the apt-started worker is kept. It is running on final configuration
  (hashes unchanged, §B). Hagistack's decision is taken about 2 s **before**
  the worker even sends its lock request (hgf1-1: "already running" 08:38:27.261,
  lock request 08:38:29.969605), so no check at that point could see F-NEW-1.
- **Fresh install (checked, not assumed):** the worker crash-loops on the
  stock sqlite config (`Restart=on-failure`). On hgf1-4 the final start was
  **systemd's** restart at 08:29:09.063, after the config writes at
  08:29:06.478 / .847. Hagistack then judged it current, which was correct
  with a 2 s margin. Hagistack does **not** itself guarantee a restart after
  the final write: the check is second-resolution, the two files are written
  about 0.4 s apart, and the unit restarts itself concurrently. This is a
  separate latent gap (§S, O-A), not the cause of F-NEW-1. It also means
  the WP-A evidence phrase "until Hagistack configures and restarts them"
  (§10.2 there) is inaccurate for the fresh path.

## F. Failure signature

For one worker start (MainPID *m*, maintenance child *c*):

**F-NEW-1 PRESENT** when all hold:

- the child's NB session sent `lock ["ovn_db_inconsistencies_periodics"]` and
  the server replied `{"locked": true}` (pcap);
- within 60 s after `MaintenanceWorker process has finished the post
  initialization`, the log has ≥ 10 lines from *m*/*c* matching
  `ERROR … configured to require a database lock` and at least one
  `OVN maintenance task <x> failed` where *x* is `@has_lock_periodic`;
- the unit is `active/running`, and the config was not rewritten after the
  start.

In every affected case the steady state was exactly 348 `NOT_LOCKED` lines
and 60 failed tasks per minute, with no lock traffic on the socket.

**F-NEW-1 ABSENT** when the same start logs 0 such lines over ≥ 60 s after
post-initialization, and lock-guarded tasks (e.g. `check_fdb_aging_settings`)
log `finished`.

## G. Experiment matrix

New hosts hgf1-1…4 (n2-standard-4, `ubuntu-2604-resolute-amd64-v20260918`).
Passive instruments on every host: `tcpdump -i lo tcp port 6641` from before
each experiment, and an `ss -tnp` sampler every 2 s mapping client ports to PIDs.

| Trial | Start path | Old/new state | Result | Time to failure | Recovery | Notes |
|---|---|---|---|---|---|---|
| hgf1-4 fresh | Hagistack all-in-one; final start by systemd crash-loop restart | none → cb3154a | ABSENT | — | — | lock granted 187 µs after request, single write |
| hgf1-1 real | apt postinst during candidate run | real 7a20dbe → cb3154a | ABSENT | — | — | single write |
| hgf1-2 real | apt postinst during candidate run | real 7a20dbe → cb3154a | ABSENT | — | — | **request written twice** (same id), second reply "must issue unlock"; still healthy |
| hgf1-3 real | apt postinst during candidate run | real 7a20dbe → cb3154a | ABSENT | — | — | single write |
| R0 (hgf1-1) | `systemctl restart`, idle | converged | 14 ABSENT, **1 PRESENT** (start 15) | 0.10 s after post-init | only after the probe (§L) | no apt, no load |
| R1 (hgf1-2) | `systemctl restart`, all CPUs busy | converged | 23 ABSENT, **1 PRESENT** (start 24) | 0.15 s | only after worker restart (§M) | |
| A0 (hgf1-3) | apt remove/install (N12 style), idle | reconstructed old state | 19 ABSENT, **1 PRESENT** (start 20) | 0.10 s | **none in 35.7 min** (08:57:28.716 → 09:33:08.997, never touched) | |
| A1 (hgf1-4) | apt remove/install, all CPUs busy | reconstructed old state | 1 ABSENT, **1 PRESENT** (start 2) | 0.15 s | only after the probe (§L) | |
| hgf1-2 restart control | `systemctl restart` of the affected worker | converged | ABSENT | — | — | new session, fresh `lock`, granted |

Totals this investigation: 66 worker starts, **4 affected (6 %)**, on all
four start-path/load combinations. The server granted the lock in 66 of 66
cases (reply latency over the 61 trial starts 137–1087 µs, median 184 µs). Including the earlier WP-A
run: 6 affected in 74 observed starts.

Duplicate write of the `lock` request (same id twice): 7 starts, 4 affected, 3
healthy. **Affected starts without a duplicate: 0.** The duplicate write means
two threads flushed the same python-ovs `jsonrpc.Connection` output buffer,
that is, the connection thread was running I/O on the session at the instant
the main thread sent `lock`. That is the precondition of the race. It is
necessary in every observed case, but not sufficient.

## H. Affected timeline (hgf1-4, trial A1, start 2)

| UTC | Event |
|---|---|
| 08:46:27.215 | trial starts (apt: install neutron-server, then the maintenance worker) |
| 08:47:14.827 | systemd `Started neutron-ovn-maintenance-worker.service` (postinst), MainPID 31397 |
| 08:47:15.947 | `OVN maintenance process starting...` |
| 08:47:17.203 / 17.219543 | `Getting OvsdbNbOvnIdl for MaintenanceWorker`; NB TCP connect from port 52044 (child 31481) |
| 08:47:37.319581 | C>S `lock id=10 ["ovn_db_inconsistencies_periodics"]` |
| 08:47:37.319775 | S>C `id=10 {"locked": true}` (194 µs) |
| 08:47:37.319927 | C>S the same `lock id=10` again (duplicate write) |
| 08:47:37.320057 | S>C `id=10` error `must issue "unlock" before new "lock"` |
| 08:47:37.322 | `Maintenance task thread has started`; `…finished the post initialization` |
| 08:47:37.467 | first `NOT_LOCKED`; `check_fdb_aging_settings failed after 0.065 seconds` |
| 08:47:37 → 09:09:04 | 348 `NOT_LOCKED`/min, 60 failed tasks/min, socket idle; unit `active`, `Result=success`, `NRestarts=0` |
| 09:09:01.238 | single probe (§L) |
| 09:09:04.241068 | S>C `locked` notification to port 52044 |
| after | 0 `NOT_LOCKED`; lock-guarded tasks `finished`; same PID |

## I. Healthy control timeline (hgf1-1, real transition)

| UTC | Event |
|---|---|
| 08:38:05.859 | Hagistack: `installing: neutron-ovn-maintenance-worker (replacing the transitional neutron-server)` |
| 08:38:07 | unit start (postinst), MainPID 29187 |
| 08:38:08.872 | `OVN maintenance process starting...` |
| 08:38:09.889972 | NB connect, port 39204 |
| 08:38:24.054 | Hagistack: apache2 reloaded |
| 08:38:27.261 | Hagistack: `neutron-ovn-maintenance-worker already running with the current configuration` |
| 08:38:29.969605 | C>S `lock id=10` (single write) |
| 08:38:29.969743 | S>C `{"locked": true}` |
| 08:38:29.971 | post-initialization finished; 23 tasks finished, 0 failed |

The healthy and affected sequences are the same up to the lock exchange.
The difference is inside the process.

## J. Lock / hash-ring state

- **Server:** the affected session **owned** the lock. A second client's
  `lock` got `{"locked": false}` on both affected hosts probed, and the owner's
  release (restart) or the server's re-notification (probe) behaved as for an
  owner.
- **Client:** `idl.has_lock=False`, `is_lock_contended=False`. Established by
  behaviour (python-ovs `NOT_LOCKED` requires `has_lock=False`; Neutron ran
  `@has_lock_periodic` tasks, which requires `is_lock_contended=False`) and
  reproduced in-process (§L, harness: `_lock_request_id` still set, reply
  already consumed).
- **Hash ring:** `neutron.ovn_hash_ring` on the affected host held only the 4
  Apache WSGI workers (group `mechanism_driver`), all updating every few
  seconds. The maintenance worker is not a ring member. Not involved.

So the "no lock" state is **neither** a missing server-side named lock **nor**
hash-ring non-ownership. It is python-ovs IDL client state that disagrees with
the server.

## K. Passive diagnostics (before any active step)

All read-only: log counts, `systemctl show`, `/proc/<pid>/cmdline` and
`status`, config `stat`/`sha256sum`, `ss -tnpi`, `SELECT` from
`ovn_hash_ring`, NB server log, and a **copy** of the running pcap.

- Worker command line uses `/etc/neutron/neutron.conf` and `ml2_conf.ini`;
  configs last written 08:29:06, worker started 08:47:14.
- NB socket established, idle (`lastsnd`/`lastrcv` ≈ 4.8 s, no bytes in queue):
  refused transactions never reach the wire.
- ovsdb-server NB log: nothing after startup at INFO level.
- **No spontaneous recovery in any affected worker left alone:** hgf1-4 21 min,
  hgf1-1 21 min, hgf1-2 21 min, hgf1-3 35.7 min (still stuck when observation
  ended; see §U). Each at a constant 348 `NOT_LOCKED`/min.

## L. Probe effect

The earlier command was reproduced exactly:
`sudo timeout 3 ovsdb-client lock tcp:127.0.0.1:6641 ovn_db_inconsistencies_periodics`.
It is **not** read-only on the lock. It opens a new NB session, sends `lock`
(WAIT), and is queued as a waiter. When `timeout` kills it, its disconnect
removes that waiter, and ovsdb-server then sends a `locked` notification to
the current owner.

| Host | Stuck for | Probe reply | Probe FIN | Server → worker | Last `NOT_LOCKED` | After |
|---|---|---|---|---|---|---|
| hgf1-4 | 21 min | `{"locked": false}` 09:09:01.238803 | 09:09:04.240589 | `locked` 09:09:04.241068 | 09:09:02.785 | 0 errors, tasks finish, same PID |
| hgf1-1 | 21 min | `{"locked": false}` 09:14:08.789091 | 09:14:11.790850 | `locked` 09:14:11.791203 | 09:14:10.621 | 0 errors, tasks finish, same PID |

The recovery was reproduced **in-process** with a standalone harness
(`lockrace.py`), using the deployed python-ovs/ovsdbapp against the real NB
server with a separate lock name `hgf_test_lock` and no data writes:

| Mode | Result |
|---|---|
| Neutron ordering (connection thread running, `set_lock` from main thread), window between send and id assignment widened by `sleep(0.02)` | **5/5 stuck**: `idl.has_lock=False is_lock_contended=False _lock_request_id=<n> neutron_has_lock=True` |
| same, stuck IDL held, external probe on `hgf_test_lock` | probe `{"locked": false}`; afterwards `idl.has_lock=True` |
| upstream-master ordering (`set_lock` before the connection thread starts), same widened window | **0/5 stuck** |
| Neutron ordering, not widened, idle host | 0/150 |
| Neutron ordering, not widened, all CPUs busy | 0/150 |

The minimal two-thread harness does not hit the natural window. The real
worker does (4/66), and every time its connection thread was driving the same
session at that instant (duplicate-write marker). The mechanism is demonstrated
deterministically; the natural trigger is characterized statistically.

## M. Systemd / config comparison

| | Healthy (hgf1-2 after restart) | Affected (hgf1-3) |
|---|---|---|
| ActiveState/SubState/Result | active/running/success | active/running/success |
| NRestarts | 0 | 0 |
| Type / Restart / NotifyAccess / WatchdogUSec | simple / on-failure / none / 0 | same |
| Unit file / init script SHA-256 | `61ff3a15…` / `6cfcb26d…` | same |
| ExecMainStart vs config mtime | after | after |
| Effective NB endpoint | `tcp:127.0.0.1:6641` | same |

systemd cannot distinguish them, and nothing in the unit signals readiness.
Hagistack's `service_active`/`service_apply` therefore cannot detect F-NEW-1,
and its decision is taken before the lock is even requested.

**Restart control (hgf1-2):** after 21 min stuck, `systemctl restart` closed
the stuck session (FIN; lock released), and the new session sent a new `lock`
and got `{"locked": true}` → 0 errors, 23 tasks finished. Config, ordering,
OVN readiness and hash ring were unchanged. Restart cures by **re-running the
same race**, which it wins about 94 % of the time.

## N. Error trace

```
ovsdbapp.backend.ovs_idl.transaction: OVSDB Error: The transaction failed because the IDL has
  been configured to require a database lock but didn't get it yet or has already lost it
RuntimeError  (ovsdbapp transaction.py:123 do_commit, status == txn.NOT_LOCKED)
  <- ovsdbapp connection.py:127 run: txn.results.put(txn.do_commit())
  <- ovsdbapp api.py:71 __exit__: self.commit()
  <- neutron impl_idl_ovn.py:273 transaction
  <- neutron maintenance.py:840 check_fdb_aging_settings: with self._nb_idl.transaction(check_error=True)
  <- neutron maintenance.py:110 log_maintenance_task wrapper
futurist.periodics: Failed to call immediate '...DBInconsistenciesPeriodics.check_fdb_aging_settings'
origin: python-ovs idl.py Transaction.commit: if self.idl.lock_name and not self.idl.has_lock -> NOT_LOCKED
```

Failing tasks (all `@has_lock_periodic`): `check_fdb_aging_settings`,
`check_router_default_route_empty_dst_ip`, `set_fip_distributed_flag`,
`update_ha_failover`, `update_mac_aging_settings`, `configure_nb_global`.
Every NB **write** fails. Reads through the IDL cache are unaffected, and
periodics whose check finds nothing to write still log `finished`. SB is not
involved (the lock is on the NB IDL only).

## O. Upstream / packaging research

| Source | Relation |
|---|---|
| Neutron **master** `maintenance.py`: `has_lock` returns `self._idl.has_lock`; `__init__` no longer calls `set_lock` (fetched from opendev raw, 2026-09-30) | **Exact match** for both implicated lines |
| Neutron **master** `impl_idl_ovn.py` `OvsdbNbOvnIdl.from_worker`: `idl_.set_lock(worker_class.lock_name)` immediately after creating the IDL, before `connection.Connection` | **Exact match**: removes the cross-thread call |
| Neutron **stable/2026.1** `maintenance.py`: still `not self._idl.is_lock_contended` and `set_lock` in `__init__` | Confirms the shipped series is unfixed |
| ovsdbapp master `connection.py`: `_check_lock_change()` / `notify_lock` tracking | Related (lock-transition handling), not required for the diagnosis |
| A release note describing the `has_lock`/`is_lock_contended` fix ("both are False when the lock has been requested but the server has not yet replied … especially during startup") | **Seen only in search-engine snippets**; not found on the rendered unreleased or 2026.1 release-note pages. Unverified; no bug number found |
| Launchpad #1927077 "[OVN] Missing lock check in check_for_mcast_flood_reports" | Similar symptom (same NOT_LOCKED message), different cause (missing guard, old release) |
| Ubuntu packaging (`neutron` 2:28.0.2-0ubuntu1) | No Ubuntu delta in `maintenance.py`; package start behaviour is standard debhelper |

No report was found of the python-ovs `_lock_request_id` assignment-after-send
window itself; upstream master avoids it by ordering.

## P. Hypotheses

| Hypothesis | Result | Evidence |
|---|---|---|
| H1 apt starts worker before final configuration | **DISPROVED** as cause | Real transitions: config unchanged, older than start (§B, hgf1-1…3). Affected starts with final config on all paths. On fresh installs apt does start it on stock config, but that process crash-loops and is replaced |
| H2 Hagistack fails to restart an apt-started worker after config convergence | **DISPROVED** as cause; latent gap noted | No config change to restart for. Restart path (R0/R1) fails too. Fresh-path restart relies on systemd crash-loop timing (§E) |
| H3 startup races OVN NB readiness | **DISPROVED** | NB connected 20 s before the lock request; server answered every lock request with a grant (66/66) |
| H4 ovsdbapp/python-ovs lock/reconnect race | **SUPPORTED** (as a Neutron-caller thread race over python-ovs) | Source (§C); wire: grant received, client acts unlocked (§H); duplicate write proves concurrent I/O; harness 5/5 vs 0/5 by ordering (§L); upstream master changed exactly this |
| H5 hash-ring stale/ownership | **DISPROVED** | Worker not in ring; ring healthy (§J) |
| H6 server-side lock not re-evaluated until another event | **DISPROVED** as cause; its converse explains the probe | Server state was correct (owner = worker). The probe works through a server re-notification on waiter removal (§C, §L) |
| H7 probe recovery was coincidence | **DISPROVED** | Reproduced on 2 hosts to the millisecond on the wire, plus in-process; untouched workers never recovered (21–35.7 min) |
| H8 package/service ordering differs materially between fresh install and convergence | **DISPROVED** as cause | Plain `systemctl restart` reproduces (R0 idle, R1 loaded). Earlier 2/5 vs 0/3 was sample size |
| H9 Neutron `has_lock = not is_lock_contended` turns a missing reply into "owner" | **SUPPORTED** (contributing, and why every task fails) | Guarded tasks ran and failed (§N); upstream master changed it |

## Q. Root-cause assessment

**ROOT CAUSE: PROVEN**

Narrowly: in Neutron 28.0.2, `DBInconsistenciesPeriodics.__init__` calls
python-ovs `Idl.set_lock()` from the maintenance worker's main thread while
ovsdbapp's connection thread is already running `Idl.run()` on the same IDL.
python-ovs 3.7.1 records the lock request id only after sending, so the
server's `{"locked": true}` can be consumed and discarded in between. The IDL
is then permanently `has_lock=False, is_lock_contended=False`. Neutron's
`has_lock = not is_lock_contended` reports it as the owner and runs every task,
and python-ovs refuses every write client-side.

Against the standard:

- **Why only some starts fail:** a thread race, about 6 % per start. It needs
  the connection thread to be driving the session at the instant of `set_lock`
  (duplicate-write marker in 4/4 failures).
- **Why the earlier "fresh/systemd" starts looked healthy:** they were not
  immune. `systemctl restart` failed 2 times out of 39 here; 0/3 before was
  sample size.
- **Why it persists:** refused transactions send nothing, no inactivity probes,
  no reconnect; the server already considers it owner.
- **Why writes fail:** `Transaction.commit` `NOT_LOCKED`.
- **Why the probe correlates:** ovsdb-server re-sends `locked` to the owner when
  any waiter disconnects; python-ovs accepts it without an id check.

Not directly observed: the individual interleaving inside a naturally affected
worker. It is the only code path consistent with the wire. A second call would
use a new id, reconnects and `stolen` would be on the wire, and none was. It is
also demonstrated deterministically in the harness.

## R. WP-A classification

**F-NEW-1: UPSTREAM/PACKAGING DEFECT EXPOSED BY WP-A**

The defect is in Neutron 28.0.2 (stable/2026.1, as packaged by Ubuntu) on
top of python-ovs thread semantics, and it is fixed on Neutron master.
Hagistack's code neither causes nor worsens it. But WP-A makes Hagistack run
this worker, and WP-A-supported states do **not** reliably converge to a
healthy worker:

- any start (fresh install, existing-host convergence, a later reboot or
  auto-restart) has about a 6 % chance of producing a worker that stays broken
  indefinitely while systemd and `hagistack status` report it `active`;
- while broken, no maintenance repair of Neutron/OVN inconsistencies happens,
  which was F02's purpose.

On Rocky the same Neutron code runs (the self-built 28.0.2 has the same
`maintenance.py`). The Rocky python-ovs build and its natural rate were not
tested here, so Rocky must be presumed exposed.

## S. Remediation options (analysis only; nothing implemented)

| Option | Mechanism addressed | Scope | Idempotency | Fresh / existing host | Distros | Testing needed |
|---|---|---|---|---|---|---|
| 1. Upstream fix: backport the master change (`set_lock` in `from_worker` before the connection starts; `has_lock` via `idl.has_lock`) to stable/2026.1 → Ubuntu SRU | the race itself, and the misleading `has_lock` | Neutron | n/a | both, and every later restart | Ubuntu via SRU; **Rocky: Hagistack already patches the neutron spec, so the backport could be carried as a spec patch** | upstream CI; for Rocky, rebuild + repeat §G trials (expect 0) |
| 2. Hagistack post-start verification (controller only, where the worker runs): at the end of `phase_neutron`, wait for the current worker's post-initialization, then check the log of the **current PID tree** for `NOT_LOCKED`; if present, restart the worker and re-check, bounded (e.g. 3 attempts), and fail loudly if still stuck | detects the state and re-rolls the race | one unit, one phase | yes (does nothing on a healthy worker) | both paths | both | trials with the same F-signature; cost ≈ 25–40 s wait per run |
| 3. Replace "restart after final config" by a guaranteed restart | does not address it | — | — | — | — | disproved (§G R0/R1) |
| 4. Lock "nudge" (`ovsdb-client lock` + disconnect after start) | heals via ovsdb-server re-notification | one command | yes, benign on a healthy owner | both | both | relies on an undocumented server behaviour; **not recommended** |
| 5. Patch installed Python files on Ubuntu | the race | — | — | — | — | **not acceptable** (modifies distro package files) |

**Smallest supported option:** **Option 2** for Hagistack. It is a narrow,
evidence-based verification of the one unit WP-A adds. It is deterministic in
detection, and bounded restarts leave about 0.02 % residual risk per run. Pair
it with **Option 1** as the real fix: report upstream/Ubuntu for 2026.1, and
for Rocky consider carrying the backport in `spec-patches/neutron.patch`.
Option 2 does not protect starts that happen outside a Hagistack run (reboot,
auto-restart). That limitation must be stated wherever the option is accepted.

**Separate latent observation O-A (not F-NEW-1):** on fresh installs the
worker's last start is often systemd's crash-loop restart, and Hagistack's
restart decision is a second-resolution mtime comparison. A restart that
reads a partially written configuration within the same second would be kept.
Not observed; recorded only.

## T. WP-A merge status

**WP-A MERGE: HOLD**

F-NEW-1 can affect every supported WP-A path (fresh and existing-host, both
distros by code). Being upstream does not clear it. The decision needed is
whether to add Option 2 (and/or carry Option 1 on Rocky) before merge, or to
merge with the defect documented as a known upstream issue.

## U. Cleanup

Four disposable instances hgf1-1…4 were created for this investigation and
deleted with their disks after the evidence was bundled (details in the final
report). hgf1-3 was still stuck when its observation ended and was deleted
untouched.

## V. Mutation summary

- product files modified: 0
- test files modified: 0
- docs modified: 0 (this report is new and **untracked**)
- staged files: 0; commits: 0; pushes: 0; PRs: 0; tags/releases: 0

**F-NEW-1 PRODUCT MUTATIONS: ZERO**

---

### Evidence files (outside Git)

`raw/hgf-bundle-hgf1-{1,2,4}.tgz` (pcaps, sampler logs, maintenance logs,
journals, trial tables, timestamped Hagistack logs), `raw/hgf-bundle-hgf1-3.tgz`,
`raw/trialwire-all.txt`, `raw/lockrace-hgf1-2.txt`, `raw/hgf1-4-probe.txt`,
`raw/hgf1-1-probe.txt`, `raw/hgf1-2-restart-control.txt`,
`raw/systemd-compare.txt`, `raw/ubuntu-package-contract.txt`,
`interventions.txt`, `ledger.txt`, and the tools `ovsdb_lockwire.py`,
`sampler.sh`, `classify.sh`, `trials.sh`, `trialwire.sh`, `lockrace.py`.
