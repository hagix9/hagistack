# F-NEW-1 on Ubuntu 26.04: deferred closeout (state record)

Recorded 2026-10-01. **This is a state and continuation record, not an audit, a fix, or a waiver.** It preserves
a deliberate pause. No external action was taken: no Gerrit change, account, credential or review, no Launchpad
change, no Ubuntu upload or SRU, no push, PR, tag or release.

Companion reports (not rewritten here):
`F-NEW-1_UBUNTU_RESOLUTION_REASSESSMENT_2026-10-01.md`,
`F-NEW-1_NEUTRON_STABLE_2026_1_BACKPORT_PREPARATION_2026-10-01.md`,
`F-NEW-1_UBUNTU_RESOLUTION_DECISION_GATE_2026-10-01.md`.

---

## Current state

| | |
|---|---|
| ROCKY F-NEW-1 ROOT FIX | **CLOSED** (frozen; not touched) |
| UBUNTU F-NEW-1 | **DEFERRED / OPEN** |
| UBUNTU DISTRO-PACKAGE MODEL | PRESERVABLE AFTER EXTERNAL ACTION |
| STABLE/2026.1 BACKPORT | READY TO SUBMIT **as of the decision-gate snapshot** (not a permanent state) |
| UBUNTU SRU | READY TO PREPARE **as of the decision-gate snapshot** |
| UBUNTU WP-A STATUS | **HOLD** |
| WP-A MERGE | **HOLD** |

"Deferred" here means: root cause known, a supported resolution path known, external action required, and that
external action intentionally postponed. It does **not** mean fixed, closed, accepted, waived, won't-fix, or merge-ready.

## A. Why Ubuntu is being deferred

The only supported way to fix Ubuntu 26.04 without turning Hagistack into the maintainer of a private Ubuntu
Neutron package is an action by people outside this repository: a stable/2026.1 backport reviewed and merged by
upstream stable maintainers (which needs an OpenDev Gerrit contributor identity that does not exist for this work yet),
followed by an Ubuntu SRU. The project chose to pause instead of taking a package-model change or a mitigation.

## B. What is already known (decision-gate snapshot)

- **Root cause (proven):** Neutron's OVN maintenance worker calls `Idl.set_lock()` from its main thread after the ovsdbapp
  connection thread is already running. python-ovs records the lock request id only after sending, so the connection thread can consume the
  server's `{"locked": true}` reply in that window and drop it. The server regards the worker as the owner, the client has
  `has_lock=False`, Neutron's `not is_lock_contended` still treats it as usable, every guarded write fails with `NOT_LOCKED`, and the state
  persisted for the whole untouched observation windows (longest 35.7 min) until a separate lock waiter caused the server to re-notify the owner.
  Natural rate on Ubuntu 26.04 hosts was 4 of 66 worker starts. (Source: the committed investigation report.)
- **Prepared causal pair** (kept exactly as prepared, not modified here):
  1. `83f1d8305651a0ab23629c88d70bfa237055158c` "Ensure MaintenanceWorker lock set before connect" (Change-Id `Iaefe1e2cc86ddd55c9053fde66353b2a333e1e98`, Related-Bug #2155155)
  2. `91abb5e720e1c515dbfbe9b2313fbdff92b2abbf` "Only set the maintenance worker lock on the worker" (Change-Id `I74145ef1407856b7ec75de87daa2270b452b6c70`, Closes-Bug #2156979)

  They must be considered together. On stable/2026.1 (and on Ubuntu's 28.0.2) the `RpcWorker` shares the `BaseOvnIdl` branch of `from_worker()`
  with the `MaintenanceWorker`; commit 1 alone would make every RPC worker, and every direct `from_worker(MaintenanceWorker)` caller
  (sync-util, upgrade check), request the maintenance lock, and an RPC worker that starts first would leave the real maintenance worker contended.
  Commit 2 restricts the lock to the class that has `lock_name` set in `post_fork_initialize()`.
- **`c695003d1012b911aa7c3f604d6d169d2567521c` is NOT part of the prepared minimal pair.** It is related and defensive, conflicts on stable/2026.1
  (`neutron/services/bgp/reconciler.py`), and was deliberately excluded from the audited Rocky fix.
- **Historical snapshot, not a current fact:** *stable/2026.1 HEAD observed at decision time:*
  `29d4ee42e2e7601b7116a27300d7e035464bc868` (2026-09-30T22:39:46Z, `28.0.2-20`). The earlier preparation report was written on base
  `8c1075228f41a95351567be57f5bfb3ff8146ed2`; it was found stale-but-compatible (the two commits in between are an unrelated DNS maintenance task).
  The pair applied cleanly to both bases, and in the same snapshot all three commits were absent from stable/2026.1.
- **Ubuntu 26.04 at the snapshot:** `neutron 2:28.0.2-0ubuntu1` (resolute-updates, published 2026-09-24; also in proposed as the same upload); source
  identical to upstream 28.0.2 in all maintenance/OVSDB files; Ubuntu patches touch other files; no newer upload; no Launchpad/SRU item for this issue.
  Ubuntu's development series carries the fix via Neutron 29.0.0~rc1 (verified from source).
- **Recorded local prepared stack** (disposable clone, not pushed): Change 1 `46256f84578d62e04e45f7d838c850aa518bc2e5`, Change 2
  `91bb432c5c34acc76edfb597fd0d2fd11afcbc56` on `8c1075228f`; rebased copy `39af200c416b…` / `5e01a44fd223…` on `29d4ee42e2`.
- **Raw evidence** (outside Git; not copied into Git):
  - `/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-neutron-stable-backport-prep-2026-10-01/package/` (231 files; `SHA256SUMS` SHA-256 `f0fe75c46273219c6393c4317e56fa2f27d9af85f3f5887cd9bda1d913d952d8`; contains the series bundle `patches/fnew1-2026.1-series.bundle`, patches, `REVIEWER_JUSTIFICATION.md`, harness and logs)
  - `/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-ubuntu-decision-gate-2026-10-01/evidence/` (103 files; `SHA256SUMS` SHA-256 `85ed11ac7de5744f9f6e2670d1abe2fcc3d9ce2f76ea6765765e4d72c14fd567`)
  - `/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-ubuntu-reassessment-2026-10-01/`

  Both manifests verified with 0 mismatches when this record was written. These are temporary workspaces; keep them until Ubuntu is closed or this record is superseded. The test
  scripts expect space-free symlinks (`/private/tmp/hgnp`, `/private/tmp/hgdg`) to those directories, which must be recreated if needed.

## C. What has NOT been done

- No change submitted to OpenDev Gerrit; no OpenDev account, SSH key or credential created or configured; no review or comment posted.
- No Launchpad bug filed or modified; no 2026.1 series task added to LP #2155155 / #2156979.
- No Ubuntu source package uploaded, no SRU filed, no Ubuntu bug or task created.
- No Hagistack-private Ubuntu Neutron package, no runtime restart or health-check mitigation, no external lock waiter.
- No Ubuntu runtime acceptance of a package containing the fix; no real-`ovsdb-server` re-run of the stable/2026.1 regression (the preparation's deterministic test used an OVSDB protocol stub).
- No push, PR, tag or release of Hagistack.

## D. The exact external dependency that remains

In order, each an event outside Hagistack's control:
1. an OpenDev Gerrit contributor identity, then upstream stable/2026.1 review and merge of the pair (two stable-maintainer approvals);
2. a Neutron 28.0.x release (none was requested or scheduled at the snapshot; the 28.x tags were 2026-04-01, 2026-07-01, 2026-09-11);
3. an Ubuntu SRU: either the point-release SRU for that release, or a direct cherry-pick SRU (acceptance not assured; upstream-first order "when possible");
4. publication of a supported Ubuntu 26.04 `neutron` package containing the pair in `-updates`.

## E. What must be revalidated when work resumes (RESUME CONTRACT)

**The old prepared stack must not be submitted blindly.** Before any prepared external action, re-establish from authoritative sources:

1. the current `openstack/neutron` `stable/2026.1` HEAD and branch status (Maintained or not);
2. whether the causal pair, or a semantically equivalent change, has already merged (check source meaning, not only subjects, SHAs and Change-Ids);
3. whether Gerrit reviews for it now exist, and their state (open, merged, abandoned, superseded), and any newer Neutron 28.0.x tag or release request;
4. whether the old prepared changes still apply cleanly **and** still mean the same thing on the then-current stable/2026.1 (the shared `from_worker()` branch, `lock_name`, `post_fork_initialize()`); re-check that `RpcWorker` still must not request the lock;
5. the current Ubuntu 26.04 `neutron` versions in release, updates, security and proposed, the source/delta, and whether the pair is present;
6. whether Ubuntu has already incorporated the fix;
7. current Launchpad / SRU state for LP #2155155, #2156979 and any Ubuntu bug or task;
8. whether the external action is still necessary at all.

Only if the fix is still absent should the prepared backport path be continued, rebased onto the then-current head with the real submitter's identity.

## F. Conditions for marking Ubuntu F-NEW-1 CLOSED

Ubuntu F-NEW-1 must **not** be marked CLOSED merely because a Gerrit review is submitted, upstream merges, an Ubuntu bug exists, an SRU is proposed, or a package enters proposed.
Closure requires at least:

1. a supported Ubuntu package containing the causal root fix is available through the intended distro-package path;
2. Hagistack consumes it without introducing a private package model;
3. the deployed source/package identity is established;
4. Ubuntu runtime acceptance shows correct maintenance-worker lock behaviour;
5. real guarded work completes;
6. the F-NEW-1 signature is absent;
7. no external lock waiter or nudge contaminates the validation (no `ovsdb-client lock`, and no client requesting `ovn_db_inconsistencies_periodics`; passive instruments only);
8. the evidence is preserved;
9. independent verification appropriate to the final change is completed.

## G. WP-A MERGE

`WP-A MERGE: HOLD` stands. Rocky closure alone does not release WP-A. Ubuntu being merely DEFERRED does not release WP-A. No waiver is created, and HOLD is not
"merge later without rechecking": when Ubuntu is eventually closed, WP-A is to be reconsidered against the then-current repository, upstream and package state.

## Other items stay separate

Not part of F-NEW-1 and not touched: O-A (fresh-install/systemd/config timing), F13b and the python333/python3333 artifact, the `tag_request` finding (`a8feb94e`), `c695003d`,
unrelated RabbitMQ and Nova shutdown noise, CLIFF. No causal dependency of Ubuntu F-NEW-1 on any of them was found.

---

UBUNTU F-NEW-1: DEFERRED / OPEN
UBUNTU RESOLUTION PATH: DOCUMENTED
STABLE/2026.1 BACKPORT: DEFERRED
UBUNTU SRU: DEFERRED
ROCKY F-NEW-1 ROOT FIX: CLOSED
UBUNTU WP-A STATUS: HOLD
WP-A MERGE: HOLD
EXTERNAL SUBMISSIONS: NONE
RESUME POINT: Revalidate current Neutron stable/2026.1 and Ubuntu 26.04 package/SRU state before performing any prepared external action.
