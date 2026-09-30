# Rocky F-NEW-1 — Runtime Evidence Remediation (2026-09-30)

Scope: close exactly the two runtime-evidence gaps left by `F-NEW-1_ROCKY_BACKPORT_INDEPENDENT_AUDIT_2026-09-30_FINAL.md`. This is **not** the independent audit; it makes no Rocky PASS claim.
Raw evidence root: `/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-runtime-evidence-remediation-2026-09-30` (manifest `SHA256SUMS`, described in §Q).

## A. Preflight

- branch `fix/rocky-neutron-maintenance-lock`; HEAD `207795084855e0fa7e3bce7124d4f0440408cfd4`; origin/master `7a20dbe1ba8cde14f9e35252e1f9074387d695d6`
- product candidate `40472e879bf55d66fb4f3ecb719d67fb180567d6` (tree `dbb2b2f1ad1dc41650a278467f20653d422966bf`); evidence commit `207795084855e0fa7e3bce7124d4f0440408cfd4` (`2077950`, tree `9f5c17357de6464b0e957bec5b35189e28f91262`)
- start status: 0 tracked modifications, 0 staged; 7 untracked (`AGENTS.md` and six `acceptance/F-NEW-1_*` reports). `git diff 40472e8 -- . ':!acceptance'` empty. `git archive --prefix=hagistack/ 40472e8` = `2208303d5a2353adedaff788bc17fb9f681d0044e9b2767e10819a83f37cf3e9` (equals the archive used before). Record: `preflight/preflight.txt`.

`PRODUCT CANDIDATE 40472e8: FROZEN`

## B. Scope — the two audit blockers

Remediation checklist (from the audit, §T/PB-01 and §U–V/PB-02):

1. **Handover guarded-work evidence.** The audit found only ownership booleans (`B.has_lock` False → True). Missing: the *same* B worker (i) not performing lock-guarded work while contended and (ii) successfully performing it after acquiring the lock.
2. **Repeated-start primary-log evidence.** Old 32-start evidence kept only `head`/`grep` counts, so guarded-task completion and error-freedom per trial could not be rebuilt from primary logs.

Both are closed by **new** runs only. Nothing from the old campaigns is counted or repaired; no product code, test, spec, manifest, RPM or systemd unit was changed.

## C. Artifact identity

Existing frozen PATH-B set, verified byte-for-byte before any VM existed and not rebuilt (`inventory/freeze-verification.txt`, produced by `scripts/freeze_inventory.py` with its own RPM header parser):

- SRPM `openstack-neutron-28.0.2-2.el10.src.rpm` `47f8cd8e7421b064fdf4ca4f15e5854917a92e01103a38cffd1bd5998f4a012c`
- 15 binary RPMs: file SHA-256, SHA256HEADER (recomputed over the header bytes) and PAYLOADDIGEST (recomputed over the compressed payload) all equal the frozen inventory. Full values: audit §L and `inventory/runtime-remediation-inventory.tsv`. Examples: `python3-neutron` file `1afd65940e98a29c2fb7c74b6daaa2a54185c9a80a1de7362e63c04228a94307`, header `b06a3b71f3b8a85a2cb6913df42881b6ea2a12be9d7faf8d76b444139658bace`, payload `7b8d4ee0b653f076e54058113a12247689524221c5210a7f7fdeb1fcc80e00e9`; `openstack-neutron-ovn-maintenance-worker` file `e0012bdd042228118289e2426577bac456d99efa0b7cd37af894c2553140e4ac`, header `838756770805abcf16cd9167f6f9b0b57024028845bfdbf1df71e66ca1dde332`, payload `e5fb1d8e78162008be2b5fca239d2dd1dd7e0f2e0dc374b816eb7190bee8110f`.
- Repository bundle `hagistack-repo-prov.tar` `54cdb9bcf1fc2057d4bfb5036ca8bf5cc27db08125ea09c2f21e83cdc325c13e`: 196 files all equal to the 196-entry frozen list, 15 neutron `-2` files, 0 neutron `-1` files, `repomd.xml` `cd0990867f8100b0205667a9d2f828f736a3dc64fb5de38391dcfa3562ee240a`.
- Hagistack candidate `rocky10.2/hagistack` `082a4a8c3879fedd1b0db262cea83fa39c63d7e4edba2536959f1e58c453e170`.

`RUNTIME REMEDIATION USES EXISTING PATH-B ARTIFACTS: YES`

## D. Deployment identity

One fresh disposable node was sufficient (single all-in-one; no guests or second node — the networking acceptance is not repeated): `hgrt-rocky1`, GCE instance id `2478655496745164699`, `n2-standard-4`, nested virtualization, 60 GB pd-balanced, image `projects/rocky-linux-cloud/global/images/rocky-linux-10-v20260910`, Rocky Linux 10.2, kernel `6.12.0-211.51.1.el10_2.x86_64`, x86_64, `/dev/kvm` present, 0 OpenStack packages before the run (`preflight/vm-preinstall-stdout.txt`, `preflight/vm-baseline-state.txt`).

Before the install: candidate tar `2208303d…`, bundle `54cdb9bc…`, `sha256sum -c` of the repository against the frozen list 0 non-OK / 196 files, `repomd.xml` equal, `rocky10.2/hagistack` `082a4a8c…`. After the campaign (`final/installed-vs-frozen-inventory.txt`, computed offline from the VM's raw `rpm -qa` and `dnf repoquery` dumps): **104/104** installed packages with `from_repo=hagistack-gazpacho` match the frozen inventory by NEVRA + SHA256HEADER + PAYLOADDIGEST; the 8 installed Neutron packages are all `1:28.0.2-2.el10` from that set (`runtime-evidence/post-campaign-sanity.txt`; `packages.txt` in every trial/handover).

`DEPLOYED HAGISTACK MATCHES 40472e8: YES`

`DEPLOYED NEUTRON RPMS MATCH EXISTING PATH-B INVENTORY: YES`

## E. Handover methodology

- **A** = the production unit `neutron-ovn-maintenance-worker.service`, real `ExecStart`, real config, INFO logging.
- **B** = a *second real maintenance worker*: the same `/usr/bin/neutron-ovn-maintenance-worker` and identical config arguments as the production `ExecStart`, started as a transient unit (`systemd-run`, `User=neutron`, `Type=notify`). Only two arguments differ: `--log-file …/ovn-maintenance-worker-B.log` (so A's and B's work are separable) and `--debug` (log verbosity only; it makes futurist log each time a task is due). B therefore contends for the same OVSDB lock `ovn_db_inconsistencies_periodics` on the same NB database.
- **Real guarded operations** (`neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py`, 28.0.2 + the two upstream patches): `DBInconsistenciesPeriodics.update_ha_failover`, `set_fip_distributed_flag`, `check_fdb_aging_settings`. Code path: futurist submits the task → `has_lock_periodic` wrapper → guard `if not self.has_lock: return` where `has_lock = not self._idl.is_lock_contended` → task body (`@log_maintenance_task`, logs "Starting OVN maintenance task: …") → `self._nb_idl.set_nb_global_options(...).execute(check_error=True)` → transaction on NB_Global → INFO "OVN maintenance task … finished".
- **Observable effect**: NB_Global values. Right after A's own one-shot tasks have finished, the harness writes three sentinels with a plain OVSDB `transact` (`options:bfd-mult=17`, `options:fdb_removal_limit=77`, `external_ids:neutron:fip-distributed=hg-sentinel`) — no lock method, no `assert`. Only a lock-owning maintenance worker running those three tasks puts back the configured values (`3`, `0`, `False`). A control step shows the sentinels persist while A alone holds the lock and is finished, so A's work is distinguishable from B's.
- **Why it cannot run while B is contended**: the client-side guard returns before the body; additionally every write by a lock-configured IDL carries an OVSDB `assert` op for the lock, which ovsdb-server only accepts from the owner. (The server-side rejection is standard python-ovs/ovsdb-server behaviour and was not separately exercised here; the client guard and the sentinel observations are what this evidence shows.) **Why post-handover success shows usable ownership**: B's three tasks ran their bodies, B's session sent `assert`-carrying transactions that ovsdb-server answered without error, and the sentinels were restored.
- **Observation, all passive**: raw loopback capture of tcp/6641 (tcpdump, read-only), a ~5 Hz `ss` sampler mapping client ports to PIDs, plain `select` reads of NB_Global (about 1/s), and log reading. **No** `ovsdb-client lock`, waiter, steal, or any lock-taking client was run. This is verified from the capture (§O), not asserted: every `lock` message in both complete captures comes from a maintenance-worker session.
- Harness: `scripts/vm/handover.sh`; timeline reconstruction `scripts/handover_timeline.py`. Three runs were made (H1 primary, H2 and H3 repeats), each followed by an uncounted restart of the production unit.

## F. Handover timeline (H1, primary; `handover/H1/`)

Reconstructed by `scripts/handover_timeline.py` from raw logs, the raw pcap, the sampler and passive NB samples; action timestamps come from `events.tsv`. Full output: `handover/H1/TIMELINE.txt`.

| Step | Time (UTC, 2026-09-30) | What | Evidence |
|---|---|---|---|
| T0 | 15:07:31.804 | A start (`systemctl restart`), A = pid 34725 | `events.tsv`; `A/command.txt` |
| T1 | 15:07:35.256 | A's single `lock` request answered `{"locked":true}`; A's guarded tasks finish 15:07:55 | pcap; `logs/ovn-maintenance-worker.log.raw` |
| perturb | 15:08:01 | sentinels written (plain transact); control 6 samples, sentinels persist | `perturb.json`, `control-A-idle.txt` |
| T2 | 15:08:16.413 | B start (B = pid 36069); B's `lock` request on the wire 15:08:19.292 | `B/command.txt`; pcap |
| T3 | 15:08:19.292 | ovsdb-server replies `{"locked":false}` to B: contended (server-side); B finishes post-initialization 15:08:39 | pcap; `logs/ovn-maintenance-worker-B.log.full` |
| T4 | 15:08:39.4 – 15:10:19.4 | each guarded task comes due (futurist "Submitting … callback") **21 times** in B's log | B log (DEBUG) |
| T5 | same window | task bodies run **0** times ("Starting OVN maintenance task" absent), 0 "finished" lines; sentinels intact in **94/94** passive NB samples; 0 B transactions carry `assert` | B log; `nb-samples.jsonl`; pcap |
| T6 | 15:10:19.943 | A stopped (`systemctl stop`); unit `Result=success ExecMainStatus=0`; A's session closes 15:10:19.968 | `A/stop-state.txt`; pcap |
| T7 | 15:10:19.969 | server sends `locked` notification to B's session (no waiter/nudge; 1 ms after A's session closed, 26 ms after the stop command) | pcap |
| T8 | 15:10:24.4 – 24.6 | the same three tasks come due once more and pass the guard: "Starting…" | B log |
| T9 | 15:10:24.476 / .593 / .603 | `check_fdb_aging_settings`, `set_fip_distributed_flag`, `update_ha_failover` "finished" under pid 36069 | B log |
| T10 | 15:10:24.820 | NB_Global back to `bfd-mult=3`, `fdb_removal_limit=0`, `fip-distributed=False`; 3 `assert` transactions from B's session answered without error | passive NB samples; pcap; `effect.txt` |

Repeats: H2 (A 43813, B 45131): `locked` notification to B 15:15:05.515Z, 21 due events while contended, sentinels intact in 94/94 samples, tasks finished 15:15:10.208Z. H3 (A 50906, B 52317): `locked` notification 15:18:32.149Z, 20 due events, sentinels intact in 93/93, finished 15:18:32.927Z. Both have the identical T0–T10 structure and pass every check below (`handover/H2/TIMELINE.txt`, `handover/H3/TIMELINE.txt`).

<details><summary>H1 raw timeline output</summary>

```
A pid=34725 (production unit)  B pid=36069 (second real maintenance worker)
A session port=41220 syn=15:07:35.255Z lock_reqs=1 reply_locked=True locked_notify=None
B session port=54942 syn=15:08:19.292Z lock_reqs=1 reply_locked=False locked_notify=15:10:19.969Z
T0  A start command                  15:07:31.804Z (harness event log)
T1  A lock granted on wire            15:07:35.256Z reply {locked:true} to A's single lock request; A guarded tasks finished: {'update_ha_failover': '15:07:55.831Z', 'set_fip_distributed_flag': '15:07:55.822Z', 'check_fdb_aging_settings': '15:07:55.494Z'}
T2  B start command                  15:08:16.413Z ; B lock request 15:08:19.292Z on wire
T3  B lock reply on wire             15:08:19.292Z {locked:False} => B contended (server-side)
T7  B receives `locked` notification 15:10:19.969Z on B's session (no external waiter/nudge; A had exited at 15:10:19.943Z +stop)
T4  update_ha_failover         due/submitted while B contended: 21 times (first 15:08:39.396Z last 15:10:19.414Z)
T5  update_ha_failover         body started/finished while contended: start=0 finished=0
T8/T9 update_ha_failover       after handover: submitted=1 started=['15:10:24.601Z'] finished=['15:10:24.603Z']
T4  set_fip_distributed_flag   due/submitted while B contended: 21 times (first 15:08:39.392Z last 15:10:19.413Z)
T5  set_fip_distributed_flag   body started/finished while contended: start=0 finished=0
T8/T9 set_fip_distributed_flag after handover: submitted=1 started=['15:10:24.590Z'] finished=['15:10:24.593Z']
T4  check_fdb_aging_settings   due/submitted while B contended: 21 times (first 15:08:39.388Z last 15:10:19.407Z)
T5  check_fdb_aging_settings   body started/finished while contended: start=0 finished=0
T8/T9 check_fdb_aging_settings after handover: submitted=1 started=['15:10:24.455Z'] finished=['15:10:24.476Z']
B transactions with `assert` before handover: 0  after handover: 3  replies ok after handover: 3  replies with error (any time): 0
T5  NB sentinels observed intact in 94/94 passive NB samples between B window open and B's lock grant (15:08:39.809Z..15:10:18.875Z)
T10 first NB sample with ALL three values restored to pre-perturb (bfd-mult=3 fdb_removal_limit=0 fip-distributed=False): 15:10:24.820Z  values: {'bfd-mult': '3', 'fdb_removal_limit': '0'} False
A exit: harness stop-state: Result=success ExecMainCode=1 ExecMainStatus=0 ActiveState=inactive SubState=dead  | A session end: 15:10:19.968Z
A-vs-B attribution: A log guarded lines after B start: 0 ; A asserted transacts after B start: 0
errors: NOT_LOCKED/require-lock in A log: 0  in B log: 0 ; ERROR-level lines A/B (level column): 0 0 ; Traceback A/B: 0 0
lock/steal/unlock messages on the wire in [begin,end]: Counter({(41220, 'lock'): 1, (54942, 'lock'): 1}) -> only A and B sessions: True
```
</details>

## G. Handover negative assertion

While B was contended (H1: 15:08:19.292 → 15:10:19.969, ≥ 100 s of observation after B's post-initialization): 21 due events per guarded task, 0 task bodies executed, 0 "finished" lines, 0 `assert`-carrying transactions from B, NB sentinels intact in every one of 94 passive samples. The window is explicit, the opportunity to run is shown by the due events, and the condition is an observable NB state, not a truncated log. Same in H2 and H3. No ERROR, Traceback or NOT_LOCKED in either A's or B's log (level-column match).

`B GUARDED WORK WHILE CONTENDED: NOT EXECUTED`

## H. Handover positive assertion

After A exited and the server notified B: B's own tasks ran the bodies (log lines carry B's PID 36069, A's log has 0 guarded lines after B's start, and A's session sent 0 asserted transactions after B started), 3 of 3 tasks "finished", B's 3 `assert` transactions were accepted by ovsdb-server, and the sentinels were restored to the configured values.

`B GUARDED WORK AFTER HANDOVER: EXECUTED SUCCESSFULLY`

## I. Handover verdict

`MAINTENANCE LOCK HANDOVER WITH GUARDED WORK: PASS` (H1, H2, H3; none of the §13 failure conditions occurred: B never guarded-worked while contended, acquired the lock without a nudge, its guarded work succeeded, the real guard was used, A and B are separable by PID/log/port, no product change).

## J. Repeated-start methodology

New campaign on `hgrt-rocky1` (nothing from the old 32 counted): trial 1 = first start through the real `hagistack all-in-one` install (`command.txt`, rc 0); trials 2–21 = `systemctl restart neutron-ovn-maintenance-worker` (20); trials 22–31 = `systemctl stop …; sleep 2; systemctl start …` (10); trial 32 = `systemctl reboot` (1). This is exactly the suggested 1/20/10/1 distribution; no trial type was substituted. Between trials 1 and 2 the three handover runs (§F) were made; they are separate and not counted.

Per trial, **before** the action: journal cursor, per-file log inode+offset (`log.offsets`), unit/worker state and PID, error counters, `ss` NB sessions, NB_Global (`before.txt`); then the sentinels are written (trials 2–32) and confirmed intact immediately before the action (`pre-action-sentinel.txt`). Then exactly one start action is executed. Then only `pgrep` and `grep` of the worker log until the new worker's PID has logged the three guarded tasks "finished" (`wait.log`), a 10 s passive settle, and collection. The reboot trial is finished by a passive script (`trial-finish.sh`) that waits and collects; boot-scoped journal from early boot (`journal-boot0-complete.raw`, first entry monotonic 1.59 s) plus the pre-reboot journal are kept.

Passive capture for the whole campaign, including the reboot: `hg-fnew1-wire.service` (tcpdump on lo, tcp/6641, `-w` pcap) and `hg-fnew1-ss.service` (`ss` sampler), both `enable`d so they exist at boot, ordered `Before=` the Neutron workers. Two complete pcaps (`wire/`), one sampler log (`ss/ss.log`). Marker definitions were written before analysis: `MARKERS.md`. Decoding/indexing is offline (`scripts/wire_decode.py`, `scripts/analyze_trials.py`).

## K. Trial table (all 32; index `trials.tsv`, per-trial folders `runtime-evidence/trial-NNN/`)

`lock evidence`: worker session's single `lock` request, server reply, and asserted transactions accepted/sent. `NL/ERR` = NOT_LOCKED count / ERROR-level+Traceback+failed-task count in the maintenance log for the trial. Times are the action start.

| # | type | start | worker PID | lock evidence (passive wire) | guarded work finished (ha/fip/fdb) | NL/ERR | result | dir |
|---|---|---|---|---|---|---|---|---|
| 1 | install | 14:54:47.999Z | 21826 | port 47696 lock_req=1 reply=True asserts=4/4 ok | ha@15:00:44.145; fip@15:00:44.135; fdb@15:00:44.076 | 0/0 | HEALTHY | trial-001 |
| 2 | restart | 15:19:55.767Z | 59276 | port 56974 lock_req=1 reply=True asserts=3/3 ok | ha@15:20:19.590; fip@15:20:19.580; fdb@15:20:19.389 | 0/0 | HEALTHY | trial-002 |
| 3 | restart | 15:20:33.635Z | 60580 | port 41678 lock_req=1 reply=True asserts=3/3 ok | ha@15:20:57.498; fip@15:20:57.489; fdb@15:20:57.289 | 0/0 | HEALTHY | trial-003 |
| 4 | restart | 15:21:11.537Z | 61872 | port 33060 lock_req=1 reply=True asserts=3/3 ok | ha@15:21:35.344; fip@15:21:35.335; fdb@15:21:35.144 | 0/0 | HEALTHY | trial-004 |
| 5 | restart | 15:21:49.394Z | 63243 | port 50272 lock_req=1 reply=True asserts=3/3 ok | ha@15:22:13.240; fip@15:22:13.230; fdb@15:22:13.032 | 0/0 | HEALTHY | trial-005 |
| 6 | restart | 15:22:27.293Z | 64591 | port 45470 lock_req=1 reply=True asserts=3/3 ok | ha@15:22:51.077; fip@15:22:51.068; fdb@15:22:50.867 | 0/0 | HEALTHY | trial-006 |
| 7 | restart | 15:23:05.146Z | 65974 | port 35822 lock_req=1 reply=True asserts=3/3 ok | ha@15:23:28.981; fip@15:23:28.972; fdb@15:23:28.793 | 0/0 | HEALTHY | trial-007 |
| 8 | restart | 15:23:43.038Z | 67355 | port 33292 lock_req=1 reply=True asserts=3/3 ok | ha@15:24:06.847; fip@15:24:06.838; fdb@15:24:06.646 | 0/0 | HEALTHY | trial-008 |
| 9 | restart | 15:24:20.916Z | 68748 | port 54252 lock_req=1 reply=True asserts=3/3 ok | ha@15:24:44.757; fip@15:24:44.747; fdb@15:24:44.540 | 0/0 | HEALTHY | trial-009 |
| 10 | restart | 15:24:58.823Z | 70092 | port 57764 lock_req=1 reply=True asserts=3/3 ok | ha@15:25:22.646; fip@15:25:22.637; fdb@15:25:22.434 | 0/0 | HEALTHY | trial-010 |
| 11 | restart | 15:25:36.695Z | 71482 | port 40788 lock_req=1 reply=True asserts=3/3 ok | ha@15:26:00.563; fip@15:26:00.555; fdb@15:26:00.369 | 0/0 | HEALTHY | trial-011 |
| 12 | restart | 15:26:14.638Z | 72861 | port 56516 lock_req=1 reply=True asserts=3/3 ok | ha@15:26:38.436; fip@15:26:38.426; fdb@15:26:38.221 | 0/0 | HEALTHY | trial-012 |
| 13 | restart | 15:26:52.498Z | 74243 | port 34040 lock_req=1 reply=True asserts=3/3 ok | ha@15:27:16.331; fip@15:27:16.320; fdb@15:27:16.098 | 0/0 | HEALTHY | trial-013 |
| 14 | restart | 15:27:30.415Z | 75595 | port 51620 lock_req=1 reply=True asserts=3/3 ok | ha@15:27:54.212; fip@15:27:54.202; fdb@15:27:54.007 | 0/0 | HEALTHY | trial-014 |
| 15 | restart | 15:28:08.283Z | 76979 | port 34878 lock_req=1 reply=True asserts=3/3 ok | ha@15:28:32.114; fip@15:28:32.105; fdb@15:28:31.906 | 0/0 | HEALTHY | trial-015 |
| 16 | restart | 15:28:46.186Z | 78358 | port 47826 lock_req=1 reply=True asserts=3/3 ok | ha@15:29:09.996; fip@15:29:09.987; fdb@15:29:09.794 | 0/0 | HEALTHY | trial-016 |
| 17 | restart | 15:29:24.094Z | 79751 | port 54788 lock_req=1 reply=True asserts=3/3 ok | ha@15:29:47.998; fip@15:29:47.989; fdb@15:29:47.790 | 0/0 | HEALTHY | trial-017 |
| 18 | restart | 15:30:02.060Z | 81104 | port 44888 lock_req=1 reply=True asserts=3/3 ok | ha@15:30:25.948; fip@15:30:25.939; fdb@15:30:25.725 | 0/0 | HEALTHY | trial-018 |
| 19 | restart | 15:30:40.050Z | 82487 | port 51124 lock_req=1 reply=True asserts=3/3 ok | ha@15:31:03.940; fip@15:31:03.931; fdb@15:31:03.732 | 0/0 | HEALTHY | trial-019 |
| 20 | restart | 15:31:18.037Z | 83870 | port 44824 lock_req=1 reply=True asserts=3/3 ok | ha@15:31:41.925; fip@15:31:41.914; fdb@15:31:41.712 | 0/0 | HEALTHY | trial-020 |
| 21 | restart | 15:31:55.999Z | 85263 | port 39044 lock_req=1 reply=True asserts=3/3 ok | ha@15:32:19.933; fip@15:32:19.923; fdb@15:32:19.686 | 0/0 | HEALTHY | trial-021 |
| 22 | stopstart | 15:32:33.966Z | 86656 | port 60730 lock_req=1 reply=True asserts=3/3 ok | ha@15:32:59.788; fip@15:32:59.779; fdb@15:32:59.587 | 0/0 | HEALTHY | trial-022 |
| 23 | stopstart | 15:33:13.918Z | 88088 | port 54836 lock_req=1 reply=True asserts=3/3 ok | ha@15:33:39.721; fip@15:33:39.712; fdb@15:33:39.507 | 0/0 | HEALTHY | trial-023 |
| 24 | stopstart | 15:33:53.793Z | 89521 | port 50264 lock_req=1 reply=True asserts=3/3 ok | ha@15:34:19.617; fip@15:34:19.608; fdb@15:34:19.403 | 0/0 | HEALTHY | trial-024 |
| 25 | stopstart | 15:34:33.699Z | 90956 | port 45200 lock_req=1 reply=True asserts=3/3 ok | ha@15:34:59.548; fip@15:34:59.538; fdb@15:34:59.333 | 0/0 | HEALTHY | trial-025 |
| 26 | stopstart | 15:35:13.646Z | 92392 | port 33410 lock_req=1 reply=True asserts=3/3 ok | ha@15:35:39.617; fip@15:35:39.607; fdb@15:35:39.411 | 0/0 | HEALTHY | trial-026 |
| 27 | stopstart | 15:35:53.782Z | 93829 | port 40232 lock_req=1 reply=True asserts=3/3 ok | ha@15:36:19.654; fip@15:36:19.645; fdb@15:36:19.445 | 0/0 | HEALTHY | trial-027 |
| 28 | stopstart | 15:36:33.747Z | 95220 | port 41576 lock_req=1 reply=True asserts=3/3 ok | ha@15:36:59.645; fip@15:36:59.636; fdb@15:36:59.428 | 0/0 | HEALTHY | trial-028 |
| 29 | stopstart | 15:37:13.735Z | 96655 | port 48246 lock_req=1 reply=True asserts=3/3 ok | ha@15:37:39.617; fip@15:37:39.607; fdb@15:37:39.409 | 0/0 | HEALTHY | trial-029 |
| 30 | stopstart | 15:37:53.709Z | 98088 | port 54304 lock_req=1 reply=True asserts=3/3 ok | ha@15:38:19.576; fip@15:38:19.567; fdb@15:38:19.365 | 0/0 | HEALTHY | trial-030 |
| 31 | stopstart | 15:38:33.720Z | 99524 | port 39446 lock_req=1 reply=True asserts=3/3 ok | ha@15:38:59.588; fip@15:38:59.579; fdb@15:38:59.391 | 0/0 | HEALTHY | trial-031 |
| 32 | reboot | 15:39:29.781Z | 3009 | port 53210 lock_req=1 reply=True asserts=4/4 ok | ha@15:41:57.193; fip@15:41:57.179; fdb@15:41:56.931 | 0/0 | HEALTHY | trial-032 |

Every trial additionally shows: worker PID new and ≠ PID before, 23 maintenance tasks finished by that PID (min = max = 23), guarded-effect `RESTORED` (trial 1: n/a — no NB existed before the install; its evidence is 4/4 accepted asserted transactions and the configured values present afterwards), unit `NRestarts` unchanged, 0 lock messages from any non-worker session in the window, action-start → last guarded task finished 23.8–26.0 s for trials 2–31 (trial 32: 43.8 s after boot; trial 1: within the install). Worker PIDs are unique and each trial's PID-before equals the previous trial's PID-after (trial 2 follows the H3 cleanup start, pid 56962).

## L. Primary-log preservation

Per trial (`runtime-evidence/trial-NNN/`): `metadata.txt` (trial, type, node, boot id, wall-clock and monotonic times, PID before/after, exact command, cursor), `command.txt`/`command.rc`, `before.txt`, `after.txt`, `log.offsets`, `journal.cursor`, `journal.raw` (the complete system journal, JSON, from the cursor to the end of the trial — all units, monotonic timestamps), `logs/*.raw` (the byte range of every Neutron log written during the trial: maintenance worker, rpc-server, periodic-workers, metadata agent), `worker.raw`, `guarded-work.raw`, `lock-events.raw` (decoded lock/assert events with PIDs), `wire-slice.pcap` (raw packets of the trial window), `ss.raw`, `perturb.json`, `pre-action-nb.json`, `after-nb.json`, `effect.txt`, `wait.log`, `packages.txt`, `result.txt`, `SHA256SUMS`. Trial 1 also `install.log`; trial 32 also complete boot journals. Campaign-wide: two complete pcaps, the sampler log, the complete `/var/log/neutron` and journals of all boots (`final/`).

`COMPLETE PER-TRIAL PRIMARY LOGS PRESERVED: YES`

## M. Independent reconstruction

Two reconstructions from the preserved files only:

1. `scripts/analyze_trials.py` (with `wire_decode.py`, a pure-Python pcap/TCP/JSON-RPC decoder): 32/32 HEALTHY. Sensitivity checked on a scratch copy: removing a guarded "finished" line, injecting a NOT_LOCKED ERROR line, un-restoring a sentinel, making PID-after equal PID-before, and giving a wrong PID each flip the trial to NOT-HEALTHY; restoring returns it to HEALTHY.
2. `scripts/reconstruct_independent.py`, sharing no code with (1): per-trial `worker.raw`, `ss.raw`, `perturb/pre-action/after` JSON, and the system `tcpdump -A` on each `wire-slice.pcap`: 32/32 HEALTHY, guarded work 32/32, signature absent 32/32, agrees with the index for every trial (`runtime-evidence/independent-reconstruction.txt`).

Two checker defects were found and fixed while doing this, both in my tooling and neither in the evidence: the reconstructor initially matched `"error":null` (present in every successful OVSDB reply) and reported 0/32 — the raw text shows all 8 hits are `"error":null`, so the regex now excludes null; and an early handover grep for the word ERROR matched the DEBUG dump of the option `logging_exception_prefix` in B's log, so all signature checks use the log-level column. The ledger records both (`ledger.txt`).

`NEW START TRIALS INDEPENDENTLY RECONSTRUCTABLE: YES`

## N. Trial result

Signature check per trial (MARKERS.md S1–S8): NOT_LOCKED 0, Traceback 0, ERROR-level 0, failed guarded task 0, lock request count exactly 1 with 0 steal/unlock, lock granted, asserted transactions all accepted, no restart, guarded work and effect present — in all 32. Whole-campaign wire inventory (`wire-all-sessions.tsv`, 672 NB sessions): 41 sessions sent a lock request, all owned by `neutron-ovn-maintenance-worker` (38 granted, plus the 3 deliberately contended B workers), each exactly one request; 109 asserted transactions, 0 errors; httpd and rpc-server sessions sent no lock message. 41 = 1 install + 9 handover + 31 trials, all accounted for. The counts alone are not offered as a proof of impossibility; they add to the regression and the causal test already audited.

`NEW PATH-B START TRIALS: 32/32 HEALTHY`

`GUARDED WORK COMPLETION EVIDENCE: 32/32`

`F-NEW-1 SIGNATURE: 0/32`

`TRIAL WORK ATTRIBUTION: VERIFIED` (log PID = wire-session owner PID = recorded PID-after, new each trial)

## O. Healing intervention

Harness activity, all disclosed: before each action the harness read NB_Global and wrote the three sentinels with a plain `transact`; after the action only `pgrep`/`grep` ran until completion; NB reads follow completion. Handover runs additionally read NB about once per second. None of these sends a lock, steal or unlock message; the capture shows every lock/steal/unlock message in the whole campaign belongs to a maintenance-worker session (§N), and `lock_messages_from_non_worker_sessions=[]` in all 32 `result.txt`. No manual restart, extra worker, or waiter occurred between a trial's start action and its completion. Trial 1 is the real installer, which is the product's own start path.

`EXTERNAL LOCK NUDGE USED: NO`

`ACCEPTED TRIALS REQUIRED HEALING INTERVENTION: NO`

## P. Runtime sanity (after the campaign, after the reboot; `runtime-evidence/post-campaign-sanity.txt`)

Maintenance worker, periodic workers, rpc-server, metadata agent, ovn-northd, ovn-controller, openvswitch, httpd, RabbitMQ, MariaDB all enabled and active with `NRestarts=0`; Neutron API `GET /` 200 and `GET /v2.0/networks` with a token 200; OVN Controller Gateway and OVN Metadata agents alive/up; nova-conductor/scheduler/compute up; maintenance, periodic, metadata logs 0 ERROR/Traceback/NOT_LOCKED; product hash `082a4a8c…` and the 8 Neutron RPM header/payload digests as in §D. No guests were created (not needed for the two gaps).

Unrelated transients, kept and not classified as F-NEW-1: (a) reboot trial: 3 rpc-server workers logged 6 `impl_rabbit` "Connection refused (retrying …)" ERROR lines at 15:41:36–37 because RabbitMQ was not yet up; the maintenance worker started and completed guarded work later (post-initialization 15:41:56.760, guarded tasks 15:41:56.9–57.2); (b) at the start of the reboot, ovsdb "connection attempt failed" warnings from the old rpc-server workers and 478 `OperationalError` journal lines from nova-scheduler/conductor/compute (15:39:29–15:40:59) while MariaDB went down during shutdown; (c) WARNING lines, counted per trial in `result.txt` and not hidden: the maintenance worker logs 5–6 at every start, all benign start-up notices — deprecated options `tenant_network_types` and `api_paste_config`, `Did not find expected name "Stdattrs_common"`, `Service MaintenanceWorker is not picklable with spawn; falling back to fork`, and `Host hgrt-rocky1 found both in OVN SB DB and Neutron` (segment host mapping); periodic-workers 0–7 (the same kinds); metadata agent 0–2; rpc-server 0–21, the high values being connection-reset/refused and amqp-channel-closing warnings around the reboot. The 6 rpc-server ERROR lines are the only ERROR-level lines in any Neutron log of the whole campaign.

## Q. Evidence integrity

- evidence directory: `/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-runtime-evidence-remediation-2026-09-30`
- capture interval 2026-09-30T14:49Z (cloud baseline) – 15:48Z (cloud final); VM created 14:49, runtime capture 14:54:19Z–15:46:26Z; host `snakeMacBook-Air.local`
- 1322 files hashed (`SHA256SUMS`, `shasum -a 256 -c` 0 failures), 153,360 KiB; `SHA256SUMS` sha256 `5bb0c112824543c185f3bd1eef89dafbb8d5c3800f66f3abfc39c5e9b22a09fb`; `MANIFEST-INFO.txt` sha256 `f4d4cc8de33432ca3aff64d2849bee84d1e463b6205d81baa47cd636d4d52fb3`; the directory was made read-only before hashing. Per-trial and per-handover `SHA256SUMS` are inside each folder.
- pcap sha256: `lo6641-20260930T145419Z.pcap` `dbd13e6f6b6c43496c70af3b698aad3d0d13ce2f1d5755099ccb0ba4a0a9f485`, `lo6641-20260930T154123Z.pcap` `128ebcdf91daacf4d0f09b6e8d240a64b475e9d3c0bcd37b65a5b56eeb22de24`; `ss/ss.log` `103496023763bf49d6b9085d5761f7d567a9a20b5c387971996039ce6ccd7139`. These were re-pulled after the capture units were stopped and all analyses re-run on those final bytes.
- Old evidence directories were not modified. Secret scan (`preflight/secret-scan.txt`): no private keys, cloud tokens, literal credentials or token values; only variable names in product source and `****`-masked debug dumps.

`PRESERVED RUNTIME EVIDENCE SECRET SCAN: CLEAN`

## R. Deferred findings

`F13b: DEFERRED`

`CLIFF: DEFERRED`

`O-A: DEFERRED`

`TAG_REQUEST FINDING: DEFERRED`

`UBUNTU F-NEW-1: UNFIXED / HOLD`

## S. Cloud cleanup

Baseline (2026-09-30T14:49:10Z, `preflight/cloud-baseline.txt`): 11 instances, 11 disks, 94 snapshots (md5 `8bc28606bd88e9c99b844f5c6a8ddf09`), 6 firewall rules, 1 address. Created: `hgrt-rocky1` only (no snapshot, firewall rule, address or other disk). Deleted with `--delete-disks=all` after all evidence was pulled and hashed. Final check (`preflight/cloud-final.txt`, 15:48:50Z): 0 `hgrt-*` instances, 0 `hgrt-*` disks; disks, 94 snapshots (same md5), firewall rules and address identical to the baseline. Nothing remediation-created was left running.

External state changes, not touched and not corrected: `mikagami-validation` was TERMINATED at my baseline and RUNNING at the final check; `sinter-rc111-hv1` was RUNNING at my baseline and TERMINATED at the final check.

Local heavy work: none (no local VMs or containers); all temporary data is under `/Volumes/VGX1000 SSD/Codex/tmp/`.

## T. Mutation summary

`RUNTIME EVIDENCE REMEDIATION PRODUCT MUTATIONS: ZERO`

- tracked modifications: 0; staged files: 0; commits: 0; pushes: 0; PRs: 0; tags/releases: 0
- `40472e8` and `2077950` unchanged; HEAD still `2077950`; product, Ubuntu, tests, spec-patches, manifest, `build-rpms.sh`, README, systemd units (product) unchanged; old acceptance and audit reports unchanged (hashes recorded in `preflight/preflight.txt`)
- only new repository artifact: this report, untracked and unstaged
- harness-only, on the disposable VM: two passive capture units, a persistent-journal directory, transient units for the runs, and a second maintenance worker (§E). None of it is in the product and the VM no longer exists.

## Limits and disclosures

- One node, one build, one Rocky image: this shows the patched artifacts behave correctly in 32 production-path starts plus 3 handovers, not that a race is impossible.
- A worker's tasks in trial 1 could not be checked by sentinel (no NB before the install).
- Server-side rejection of an asserted write from a contended session was not exercised (§E).
- B ran with `--debug` and its own log file; A and the 32 trials used production logging.
- Setup hiccups, all before any counted evidence and recorded in `ledger.txt`: the first two harness units failed on SELinux labelling of scripts under `/var/lib` (fixed with `/usr/local/sbin` wrappers); the first launch of trial 1's transient unit failed with 203/EXEC before running anything and was relaunched via `/bin/bash`; the install ran with SELinux enforcing at start, as in the product's design (it sets permissive itself).
- Idempotency was not re-run (existing audited PATH-B evidence stands).

## U. Readiness

`RUNTIME EVIDENCE: READY FOR FOCUSED INDEPENDENT RECHECK`

This is not an audit PASS. The independent auditor makes the Rocky decision; WP-A stays on HOLD because Ubuntu is unfixed.

MAINTENANCE LOCK HANDOVER WITH GUARDED WORK: PASS
NEW PATH-B START TRIALS: 32/32 HEALTHY
GUARDED WORK COMPLETION EVIDENCE: 32/32
F-NEW-1 SIGNATURE: 0/32
EXTERNAL LOCK NUDGE USED: NO
RUNTIME EVIDENCE REMEDIATION PRODUCT MUTATIONS: ZERO
RUNTIME EVIDENCE: READY FOR FOCUSED INDEPENDENT RECHECK
ROCKY F-NEW-1 ROOT FIX: AWAITING INDEPENDENT RECHECK
UBUNTU WP-A STATUS: HOLD
WP-A MERGE: HOLD
