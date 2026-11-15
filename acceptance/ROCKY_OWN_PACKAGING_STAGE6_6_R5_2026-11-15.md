# Stage 6-6-R5: single-node final checks, and controller + compute acceptance preparation (2026-11-15)

Base: `33bb370` on `feat/rocky-own-packaging-s65r1`. Nothing pushed, merged, tagged or released. No GCE resource was created or changed for this stage.

The two acceptances are kept apart:
- **A. All-in-one on one node.** s66r4a passed everything but two items.
- **B. Adding a compute node.** `hagistack controller` and `compute-add` have never run on two real hosts.

## A. All-in-one: the remaining conditions

The s66r4a evidence was re-read: RPM build, release, nodocs, Horizon, documentation, OVN chassis, metadata and SSH. Its record (`ROCKY_OWN_PACKAGING_STAGE6_6_R3_2026-11-14.md`, "GCE run s66r4a") has enough to keep these items as they are, so nothing in them was changed.

Two items remained.

1. **Guest-to-guest ping after the restart.**
   - `s_accept` now has s66-g3 (booted after the restart) ping s66-g1 (booted before it), after checking that s66-g1 is still ACTIVE.
   - The ping code is now one function, `ping_pair`, used before and after the restart.
2. **Tracebacks.**
   - `traceback_count` (fixed in `33bb370`) counts 20 on s66r4a's retained journals.
   - Tracebacks are now counted per window:
     - before the restart;
     - from the restart until recovery;
     - after recovery.
   - Recovery means the after-restart checks passed, a new guest booted, and the ping across the restart succeeded.
   - Only the window after recovery is judged, after at least 120 s of observation.
   - Errors while units restart one after another are counted and kept per unit (`diag/tracebacks-accept.txt`), not judged. s66r4a's nova-compute exit and restart, and the metadata agent's `RowNotFound`, are of that kind.
   - A journal that cannot be read gives `error`, which fails the check. A window with no entry is 0.

Not verified until the next all-in-one GCE run:
- the new ping;
- the windows on a real journal.

## B. Controller + compute: what the implementation does (files read)

| Function | State |
|---|---|
| `hagistack controller` | Every all-in-one phase except nova-compute. Packages without `openstack-nova-compute`, `libvirt`, `qemu-kvm`. The controller is the gateway chassis. |
| `compute-add --controller-ip` | Order: secrets → reachability → RPM source → repositories → SELinux → packages → OVN → nova-compute → metadata agent. |
| `compute-add --local` | Adds the hypervisor to a controller. No controller phase runs again. |
| `compute-secrets` | Refuses a terminal. Prints the five compute credentials and `RPM_SET_SHA256` only. |
| `rpm-bundle` | Verifies the deployed set first and refuses to overwrite its output. |
| RPM set consistency | `controller_rpm_set_check` stops before any download when the identity is missing or malformed. `rpm_guard_consistency` stops when this node's set differs from the controller's. |
| Reachability | `phase_compute_preflight` probes the controller's ports and stops before anything is installed. |
| Cell registration | The controller sets `discover_hosts_in_cells_interval 300`; `discover-hosts` maps a new host at once. |
| Neutron/OVN | The chassis takes the host's short name and the node's own `MGMT_IP` as Geneve endpoint, `ovn-remote tcp:CONTROLLER_IP:6642`, no gateway option and no bridge mapping. The name is kept in `system-id.conf`. |
| No database on compute | The `[database]`/`[api_database]` connection keys are commented out. `compute_assert_no_db` then checks `nova.conf` and the effective oslo.config values, and stops before nova-compute starts if either still has a key. |
| Re-run | Secrets are reused, not rotated. A verified set is reused. `ini_set` and the role guard keep a re-run of a compute node a re-run. |

**Defects found and fixed in `hagistack`.**
1. **The compute preflight did not probe the Neutron API (9696) or Nova metadata (8775).**
   - nova-compute binds ports through the Neutron API.
   - The node's metadata agent proxies to Nova metadata.
   - Without them a node passed the preflight and failed later. Both ports are now probed, and README (en, ja) lists them.
2. **No MTU handling.**
   - Neutron's default `global_physnet_mtu` (1500) gives tenant networks 1442.
   - On a 1460-byte network (a GCE VPC) a full guest packet does not fit in the Geneve tunnel between two nodes. On one node nothing is tunnelled, so all-in-one never showed it.
   - `phase_neutron` now sets `global_physnet_mtu` to the MTU of the interface holding `MGMT_IP` (`mgmt_mtu`). It leaves the default with a warning when that MTU cannot be read.
   - Networks keep the MTU they were created with.

**README only (Hagistack still configures no host firewall).**
- `firewalld` is active on the GCE Rocky image: s66r4a's `units.txt` lists it as active. README now gives the commands to open the ports:
  - on the controller, the listed TCP ports and UDP 6081;
  - on a compute node, UDP 6081.
- README also states two requirements:
  - every node needs the same management MTU;
  - every node needs synchronised clocks.
- Names: Hagistack uses addresses, not host names, between nodes, so no name resolution between nodes is needed. Each node needs a distinct short host name; README already says so.

**Not changed.**
- `compute-add` does not compare its own MTU with the controller's. README and the acceptance check this, not Hagistack.

## B. The acceptance plan for one controller and one compute node

### Plan, node script and tests

**Run plan (`run-plan.json`).** It names n1 and n2 and adds the steps of the new `acceptance/stage6/s67-cluster.sh`, which reuses the helpers of `s66-node.sh`. `hs6.py` is unchanged: it already supports n2 (n2-standard-4, 60 GB, pd-standard).

**Steps of `s67-cluster.sh`, in run order.** A node knows its role from its name and refuses the other role's steps. Each step runs once and needs the step before it on that node.

| Node | Step | Checks |
|---|---|---|
| n1 | preflight … pack | The set is built and checked (s66, as in s66r4a). |
| n2 | extract, preflight | s66 preflight only; n2 builds nothing. |
| n1 | controller | <ul><li>`hagistack controller` with the new set; role and set recorded; no hypervisor packages.</li><li>Keystone, Nova API, scheduler, conductor, Neutron and Placement answer.</li><li>With no compute node: no nova-compute service, no hypervisor, a guest goes to ERROR with "No valid host"; one chassis, this host, as gateway.</li><li>`global_physnet_mtu` is the management MTU, and the tenant MTU is that − 58. The clock is synchronised.</li><li>README's firewall commands are run.</li><li>`compute-secrets` holds exactly the five names and the set id. `rpm-bundle` names the set and refuses to overwrite its output.</li><li>The handoff is offered only if every check above passed.</li></ul> |
| n2 | compute | <ul><li>The handoff is fetched and its SHA-256 confirmed.</li><li>README's credential install: `/etc/hagistack/secrets.env` root:root 0600, and the copy shredded.</li><li>Same MTU as the controller; clock synchronised.</li><li>`compute-add --controller-ip --rpm-source bundle`: the set verified as the controller's, packages with the set's headers, no API, database or broker packages.</li><li>OVS external-ids: system-id, ovn-remote, encap IP; no gateway, no bridge mapping.</li><li>No active database key; no database or admin password in `secrets.env`; no `admin-openrc`.</li><li>The units active.</li></ul> |
| n1 | cluster | <ul><li>`discover-hosts`.</li><li>nova-compute on n2 up; n2 a hypervisor; no nova-compute on n1; Placement provider.</li><li>The chassis set is exactly {n1, n2}: n1 gateway, n2 not, n2's encap IP its own address; the three agents alive.</li><li>s67-g1 and s67-g2 booted on n2: floating IPs, SSH and metadata through the tunnel; guest-to-guest ping (local to n2); a 2 MB stream from a guest arrives whole, which shows full-size packets cross the tunnel.</li><li>The controller's units restarted; after that the same registration checks, s67-g3 booted, SSH, metadata, s67-g3 pings s67-g1.</li><li>Tracebacks after recovery judged (≥120 s).</li></ul> |
| n2 | reboot | Boot id kept; reboot 20 s after the step ends. |
| n1 | after-reboot | <ul><li>Waits until n2 is down.</li><li>The registration checks again, so the same chassis names and no extra chassis.</li><li>Guests that do not answer are started (SHUTOFF) or hard-rebooted (ACTIVE).</li><li>SSH to each; s67-g1's uptime is shorter than the time since the cluster step, so its host went down; ping.</li></ul> |
| n2 | rerun | <ul><li>The boot id changed.</li><li>The local checks again.</li><li>`compute-add` again: the verified set reused; SHA-256 of `nova.conf`, the metadata agent's file, `system-id.conf`, `deployment.env`, `secrets.env` and the OVS settings unchanged.</li><li>No traceback after the re-run (≥120 s).</li></ul> |
| n1 | final | <ul><li>Registration again.</li><li>s67-g4 booted on n2, SSH, metadata, ping to s67-g1.</li><li>No failed unit; only the set's packages.</li><li>No traceback since n2 came back.</li></ul> |
| n1, n2 | evidence-c, evidence-n | `evidence-cluster.tar`, `evidence-compute.tar`, scanned for secrets as in s66. |

**The handoff.** It stands in for README's "copy over a secure channel", because the nodes share no SSH key.
- n1 offers one tar once, on its management address, to n2's address only. A runtime firewalld rule opens the port for that one source, and the offer lasts at most 1 h.
- n2 returns the SHA-256 of what it received and n1 answers whether it matches; the value is never printed.
- The transfer is plain TCP inside the run's own VPC. Both copies are deleted after use, and neither is under `out/`.

**Second and later compute nodes.** Code and tests only; no extra VM is planned.
- `test-compute-node.sh` checks that host, `my_ip`, chassis name and encap IP come from the node itself, and that the compute phases name no fixed host or address.
- The harness can create n3 and n4. A run with them needs a separate approval.

**Tests added.**
- `rocky10.2/tests/test-compute-node.sh` (28), covering:
  - the preflight probes all eight ports and stops on 9696 or 8775;
  - `mgmt_mtu` for 1460, 9000, implausible values and an exact address match;
  - `phase_neutron` sets `global_physnet_mtu`;
  - `compute-secrets` prints only the compute keys;
  - no fixed per-node values.
- `acceptance/stage6/test_s67_cluster.py`, covering:
  - roles and step order;
  - the handoff run on loopback (one transfer, file and rule removed; another address refused; SIGTERM cleans up);
  - `ini_active`, `secret_names`, `answers_empty`;
  - the text of the steps.
- `test_s66_node.py`, covering:
  - the windows run on a stand-in journal (only after-recovery is judged; the unit patterns are not globbed);
  - an unreadable journal is `error`, while an empty window is 0;
  - the ping across the restart;
  - the script can be sourced;
  - all-in-one is refused on a controller.
- `test_hs6.py`: the committed plan names n1 and n2 and every s67 step and download.

### Unchanged and still unverified

- `compute-add --local` and the stop on an RPM mismatch are not exercised in the GCE plan. `test-rpm-source.sh` covers both and needs `rpmbuild`; it was not run on this Mac.
- With `libvirt-guests` resuming guests on boot (not enabled on Rocky by default), `peer_gone` would not see n2 go down and would fail. That failure is a false FAIL, never a false PASS.

## Local results (this Mac)

| Suite | Result |
|---|---|
| `test-compute-node.sh` | 28 passed |
| `test-ovs-system-id.sh` | 20 passed |
| `test-build-own.sh` | 33 passed |
| `test_release_check` | 28 on 3.9 (1 skipped) and on 3.13 |
| `test_genspec` (3.13) | OK |
| `test_adapt` | 71 |
| `test_branding` | OK |
| `test_hs6` + `test_s66_node` + `test_s66_web` + `test_s67_cluster` | 270 of 270 on 3.9 and on 3.13 (final code) |
| `bash -n` | `hagistack`, every `rocky10.2/tests/*.sh`, `s66-node.sh`, `s67-cluster.sh` |

Not run here: `test-rpm-source.sh` and `test-env-file.sh` (need rpmbuild, createrepo_c or bash 4), `test-build-in-container.sh` and `test-build-rpms-staging.sh` (fail on this Mac before this change too).

## Independent audit (separate agent; not self-review)

**First pass: 2 BLOCKER, 1 HIGH, 4 MEDIUM, 5 LOW.** All are in `s67-cluster.sh` except M-4.
- BLOCKER:
  - B-1: the reboot timer used the step's own unit name, so no reboot would be scheduled.
  - B-2: `power_state` with `-f value` is a number, and Nova keeps a stale one until its sync.
- HIGH:
  - H-1: after-reboot could pass against a node that had not gone down yet.
- MEDIUM:
  - M-1: reboot detected from the journal's boot list.
  - M-2: the handoff was offered after a failed check.
  - M-3: no judgement of the compute node's tracebacks.
  - M-4: Hagistack does not compare the compute node's MTU itself.
- LOW:
  - fail-open empty answers;
  - the rc of `rpm-bundle`;
  - copies of secrets kept for the re-run comparison;
  - wording;
  - the README note on existing networks.

All fixed except M-4, which is recorded under "Not changed".

**Targeted re-audit: no BLOCKER or HIGH; every earlier finding confirmed fixed.** It raised two new LOWs and three NOT VERIFIED items. Four were then fixed:
- L-A: the handoff gate is checked again just before the tar is made.
- L-B: `peer_gone` needs the floating IP and three silent tries in a row.
- NV-A: a window with no entry, answered with a non-zero exit, is 0 when the journal itself reads.
- NV-B: the compute node's judged window starts after the re-run.

NV-C (libvirt-guests) is under "Unchanged and still unverified".

## Needs a real machine

Everything in s67-cluster.sh, in particular:
- the OSC columns used;
- GCE internal name resolution between the nodes;
- firewalld on the image;
- br-ex keeping 172.24.4.1 across the openvswitch restart;
- the 2 MB stream;
- the reboot behaviour;
- whether the compute-add re-run restarts units (recorded as a NOTE).

For all-in-one: the new ping and traceback windows.

## GCE run s66r5a (all-in-one, commit 0f082c1): stopped before install

Approved in chat with s66r5b ("両方を承認"); s66r5b was not started.

| Step | Result |
|---|---|
| init, network, n1, upload (tree sha256 4d896b5c…, verified) | done |
| extract, preflight, build, release, nodocs, pack | PASSED (pack 05:46Z; candidate.tar 161 003 520 bytes, sha256 c18d5b32…) |
| download candidate.tar | **failed**: gcloud's IAP tunnel raised `ConnectionReconnectTimeout` and gcloud kept running without exiting; the harness waited for `HS6_REMOTE_TIMEOUT` (14400 s) and stopped it at 09:46Z |
| download evidence-build.tar | verified (sha256 0b9accb1…) |
| install | refused by the harness: `downloads/candidate.tar must be kept first` |
| evidence | not applicable (no accept, no failed node step); evidence-final.tar does not exist |
| teardown, residual | complete; "none of run s66r5a left"; watch ended rc 0 (no limit tripped) |

About 5 h 42 min of n1 (n2-standard-8). The all-in-one acceptance (post-restart ping, traceback windows) is **not verified** on a real node.

Why it waited 4 h: a download had only the step timeout of 14400 s and nothing watched the bytes received. The temporary runner also lost the download's exit status (`dl … | tail -1` without `pipefail`) and went on to `install`; the harness refused it. The runner now sets `pipefail`.

## Stage 6-6-R5 transfer fix (hs6.py)

- `download` has its own limits: it stops when the size of the local `.part` file has not grown for `HS6_DOWNLOAD_STALL` seconds (default 120), or after `HS6_DOWNLOAD_TIMEOUT` seconds in all (default 1800). Outside the tests they are clamped to 30..600 s and 60..3600 s. A live process or log output is not progress. The size is polled every `min(5 s, stall/4)`; the cost and time guard still runs every watch interval.
- The node's `sha256sum` check gets what is left of the download's time, at most the stall time.
- A stop kills the process group: SIGTERM, then SIGKILL unless every member has ended; then it checks that no member is left. The log records why (`stalled`, `total-timeout`, guard), the seconds, the bytes received and an IAP `ConnectionReconnectTimeout`. A member left after SIGKILL exits 5 and records `process-left` in stops.jsonl, which refuses every further step.
- The `.part` file is always deleted; the file is kept only after the SHA-256 match (unchanged). No automatic retry. `install` stays refused without `candidate.tar` (unchanged).
- Not changed: the run plan (sha256 149a17c9…aa3), the tree paths (hs6.py is not in the tree), the approval format. Uploads and ssh steps keep `HS6_REMOTE_TIMEOUT` (14400 s); an IAP drop during the 1.4 MB tree upload would still wait up to the 6 h run limit (not in this task's scope).
- Not verified: that real `gcloud compute scp` (SFTP mode) grows the `.part` file as bytes arrive. If it wrote the file only at the end, a large healthy download would be stopped as stalled (fail-closed). The first real download shows it.

### Tests (this Mac)

- New class `test_hs6.DownloadStall`, 16 tests. They cover:
  - a slow download that is completed and verified;
  - a stalled download, and one that never sends a byte;
  - a trickling download stopped by the total limit;
  - a SHA-256 mismatch;
  - a hanging and an interrupted `sha256sum` check;
  - the cost and time guard during a download;
  - the limit clamps;
  - `HS6_REMOTE_TIMEOUT` not applying to downloads;
  - a child that ignores SIGTERM and holds no pipe, which is killed;
  - `process-left` for both the transfer and the check;
  - the test hook refused with a real account;
  - `install` refused after every failed case.
- Times are shortened, so no test waits 120 s or 1800 s.
- `test_hs6` + `test_s66_node` + `test_s66_web` + `test_s67_cluster`: 285 of 285 on 3.9 and on 3.13. `DownloadStall` was then run again on the final code, 16 of 16 on both. The last test was added after the full run.

### Independent audit (separate agent; not self-review)

**First pass: 0 BLOCKER, 1 HIGH, 2 MEDIUM, 6 LOW.**
- H1: `_kill_group` sent no SIGKILL once the leader had ended, so a child that ignored SIGTERM survived.
- M1: the `process-left` path was untested.
- M2: the `sha256sum` check swallowed a left process and interrupts.

All three were fixed, together with L1 (comment), L2 (wording and README for ssh and upload), and L5 (a test that proved less than its name).

**Targeted re-audit: 0 BLOCKER, HIGH or MEDIUM.** Every fix was confirmed by code and by probe. Of its LOW items:
- L-a (no regression test for an interrupted check) and L-b (a weak hook test) are now fixed.
- Left as they are:
  - L-c: an interrupt during the kill (pre-existing);
  - L-d: up to 5 s more before SIGKILL;
  - L3: a healthy download that ends near the total limit fails its check (fail-closed);
  - L4: the stall clock includes the IAP and ssh set-up;
  - L6: uploads unchanged.

NOT VERIFIED (both passes): `.part` growth with the real gcloud scp.
