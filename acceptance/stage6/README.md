# Stage 6 GCE harness (`hs6.py`)

The harness creates and deletes the GCE resources of one stage 6 run of the
own-RPM acceptance (`../ROCKY_OWN_PACKAGING_STAGE6_PLAN_2026-11-12.md`), and runs
commands on those nodes through IAP. It does not install OpenStack by itself. The
per-configuration steps in the plan are run with `hs6.py ssh` and `hs6.py upload`.

**It is dry-run unless the Owner approved the run.** Without an approval file, every
command prints the gcloud calls it would make and calls nothing, not even read-only
gcloud.

## Files

| File | Purpose |
|---|---|
| `hs6.py` | the harness (Python 3.9+, standard library only) |
| `mock_gcloud.py` | a gcloud stand-in for the tests; it contacts nothing and reads no credentials |
| `test_hs6.py` | local tests: `python3 test_hs6.py` (put `TMPDIR` on the external SSD) |
| `hs6_approve.py` | the Owner's tool: shows the conditions and signs one run's approval |
| `APPROVAL.template.json` | the shape of an Owner approval; not valid as it is (it has no signature) |

## Fixed in the code, not on the command line

- Project `<GCP_PROJECT>`, zone `asia-northeast1-a`.
- Machine types, `pd-standard` boot disks and their sizes (n1 100 GB; n2 60; n3 50;
  n4 50; u1 60).
- Image family `rocky-linux-10` from `rocky-linux-cloud`. `init` resolves it to one
  image, and every node uses that one.
- Subnet `10.86.0.0/24`. The IAP SSH range and an internal rule cover only that subnet.
- Each node is created with:
  - no external IP (`--no-address`), no service account and no scopes;
  - nested virtualisation;
  - `block-project-ssh-keys=TRUE`, so `gcloud compute ssh` puts its key on the
    instance, never in the project-wide metadata shared with Sinter's VMs;
  - `--max-run-duration` with
    `--instance-termination-action=DELETE`. The duration is the smaller of the node's
    planned hours × 1.5 and the time left before the run's limit, and at least 0.5 h
    must be left. GCE deletes the node even if nobody runs the harness any more.

The command line gives only the run id, the node name and the state directory.

## Executing (only after the Owner's approval)

Execution needs **all** of the following:

1. An approval file (`--approval FILE`, kept outside the repository) **and**
   `FILE.sig`, the Owner's SSH signature of exactly that file (see "Approving a run").
   The signature must verify against a key pinned in `OWNER_SIGNING_KEYS` in
   `hs6.py`, in the namespace `hagistack-stage6-approval`. The file has:
   - `format` 2 and a random `nonce`;
   - the run id, project and zone;
   - the gcloud account;
   - the exact `owner_statement` the harness prints for the run;
   - the SHA-256 of this `hs6.py`. Any change to the harness needs a new approval.
   - the approved `operations`, which must include `teardown`;
   - `budget_usd` of 8 or less, and `max_hours` of 6 or less;
   - `approved_at` and `expires_at`, at most 24 hours apart and covering now.
2. `HS6_EXECUTE=<run id>` in the environment.
3. The configured gcloud account, and the only active one, equal to the approved account.
   - No service-account impersonation and no `CLOUDSDK_*` identity override.
   - Every call carries `--account=<approved>`.
4. No test hook. `HS6_GCLOUD`, `HS6_NOW`, `HS6_CLOCK_FILE`, `HS6_REGISTRY` and
   `HS6_WATCH_MAX_LOOPS` work only with an approval whose account is in the reserved
   `.invalid` domain, as in the tests. With a real account they are refused. Outside
   the tests, `HS6_WATCH_INTERVAL` is kept between 5 s and 300 s.

The approval can lower the cost and time limits, never raise them. `teardown` and
`residual` still work after it has expired, so a run can always be cleaned up.

There is no `--execute` flag.

## What protects other resources

- **Generated names only.** A mutating gcloud call is refused unless all of these
  hold:
  - it has one of the exact create/delete forms;
  - its only positional target is `hagistack-s6-<rid>-(net|subnet|fw-iap|fw-int|router|nat|n1|n2|n3|n4|u1)`;
  - the project is pinned exactly once.

  Read calls are limited to exact read-only forms, and ssh/scp only to nodes of the
  run. Sinter, Mikagami (`mkg-*`) and
  `default` resources can never be targets.
- **A ledger.** `ledger.jsonl` is append-only and hash-chained, and `ledger.head`
  holds the last line's hash.
  - Every creation is written **before** the call ("create-requested"), then
    reconciled with the GCE resource id and creation time. Each node also records its
    boot disk name, id, type and size.
  - A creation the API refused (permission or quota) is "create-failed".
  - A timeout or any other error is "unknown". It counts as running, it blocks new
    work, and teardown reconciles it: it adopts a resource that appeared later and
    deletes it, or records it as never made after 15 minutes of absence.
  - A partial creation is therefore always identifiable.
  - A missing, edited or truncated ledger or baseline stops every create and every
    delete.
- **Delete checks.** A deletion goes ahead only if all of these hold:
  - the ledger says "created";
  - GCE now reports the **same id and creation time**;
  - nodes still carry the run-id label;
  - nodes have only their recorded boot disk (deleted with `--delete-disks=boot`).

  A failed deletion is checked again and retried by the next teardown. Before a node
  is recorded as gone, its boot disk is confirmed gone too.

  A label alone is never enough. A NAT has no id of its own, so its router's id and
  its name are used instead.
- **Baseline.** `init` records every existing resource as protected and refuses to
  start if any `hagistack-s6-<rid>-*` resource already exists.
  - Before each creation, an unexpected resource in the run's namespace, or a new
    external address, stops the run.
  - Other products' new resources are reported and never touched.
- **Errors.** A gcloud crash or an unclassified error is never read as "not found".
- **Run ids.** A run id is never reused: a local registry is kept under
  `~/.config/hagistack-stage6/`. `HS6_REGISTRY` is a test hook and is refused with a
  real account.
- **Project ssh-keys.** The project-wide `ssh-keys` are recorded at `init` and checked
  before and after every ssh/upload, so a key written into them stops the run. Other
  project metadata may change through other work and is not compared.
- **Remote commands.** An ssh/upload holds the lock only for its checks. A teardown is
  never blocked by a running test step. Each step's full output and exit status are
  kept in `remote/<time>-<node>-<op>.log`. A non-zero status ends with exit code 10.
- **Stops.** The run stops in each of these cases:
  - on a permission error at once (no IAM change);
  - on a quota error;
  - on a timeout, or when a resource's state is unknown;
  - while a deletion has failed or a resource is unresolved, nothing new is created;
  - an unknown resource is deleted only after teardown has adopted it: it must exist,
    be named in the run's namespace, be created after the request and, for nodes,
    carry the run-id label. Otherwise it is left for a manual check.
- **No retries.** A failed creation is not retried. One run id has one state
  directory, and a lock file prevents two operations at once.

## Cost and time guards (list prices, not final)

Prices are Tokyo list prices from Google's pricing pages (2026-11-12). Internet egress
is not verified, so it is assumed high: US$0.20/GiB for 2 GiB. Every report says
`"final": false`.

| Condition | Effect |
|---|---|
| projected total ≥ US$7 | no new resource |
| accrued ≥ US$8 | stop, and tear this run's resources down automatically |
| the run's time limit (6 h, or less if approved) since the first creation | stop, and tear down automatically |
| a node over its planned hours by more than 50 % | stop, and tear down automatically |
| the monitor cannot compute | stop new work and test steps; no automatic teardown (the view is broken) |

**What counts as torn down.** A limit is first written to `stops.jsonl`, without the
lock, so it is recorded even when the lock is busy or the teardown cannot start. Any
entry there blocks new resources and test steps for the rest of the run. The ledger
then records the stop (`guard-stop`) separately from its outcome:
- `teardown-complete`: nothing of the run is recorded as present any more;
- `teardown-incomplete`: lists what remains and why.

A teardown never deletes against a broken ledger, a different GCE id or an unclear
owner. An incomplete teardown exits with code 8 and names what is left.

**When the guards run.** The guards are checked on:
- every harness command;
- every `HS6_WATCH_INTERVAL` seconds (default 60) while an `ssh`/`upload` step runs.
  - A step that reaches a limit is killed together with everything it started (its
    own process group, TERM then KILL, with bounded waits).
  - Its output so far is kept, and the teardown follows.
  - A failed monitor kills the step, deletes nothing and records the failure.
- every interval by `hs6.py watch`, a monitor for a second terminal.
  - It holds no lock while it waits.
  - It calls GCE only to check the account at start and to tear down.
  - It does not give up: a lock held by another command, an incomplete teardown or a
    ledger read failure is recorded and retried at the next interval.
  - It ends once the run has been torn down.

**Cost figures, kept apart** (`status` and `plan` print them):
- the projection for the planned run;
- the harness's estimate of what has accrued, with the part that rests on assumptions
  shown separately;
- what is assumed or not priced: egress, and the NAT data volume;
- the actual Google Cloud bill, which the harness does not know (check Cloud Billing).

US$8 is a limit the harness enforces while it runs. It is not a cap that Google Cloud
guarantees.

Teardown is always allowed and is never refused by the cost or time guards.

## If the harness is not running

If the harness process dies, the terminal disconnects or the Mac sleeps or shuts
down, nothing in this harness acts any more.

- **Nodes.** GCE deletes each node by itself at its `--max-run-duration`, which is
  never more than planned × 1.5 and never past the run's time limit.
- **Unattended cost.** If every node was created and nobody ran the harness again,
  the estimate up to the nodes' deletion is about **US$8.54** (`hs6.py plan` prints
  it). It assumes:
  - all five nodes at their longest possible duration;
  - list prices;
  - the assumed egress (2 GiB) and NAT data (3 GiB per node);
  - 6 hours of NAT IP.

  It is an estimate, not a bound the harness can guarantee, and **US$8 is then not
  guaranteed**. The NAT IP charge after that is not included.
- **Network.** The NAT, router, firewall rules, subnet and network are **never**
  deleted by GCE itself. The NAT IP keeps costing about US$0.005/h, roughly US$0.12 a
  day, until it is removed.
- **No extra infrastructure.** Making that cleanup automatic would need something
  that keeps running and costs money: a VM, Cloud Scheduler or Cloud Functions. The
  harness adds none of these.

**Operating conditions for a real run (required):**
1. Run `hs6.py watch` in a second terminal for the whole run. Keep the Mac awake
   (`caffeinate -i`) and use a terminal session that survives disconnects (for example
   `tmux`). If `watch` itself is killed, nothing records it.
2. After the run, or after any interruption, run `hs6.py teardown` then
   `hs6.py residual`, and do not finish until `residual` reports nothing left. If the
   harness cannot do it, remove what `residual` names by hand, by exact name.
3. If the operator's machine was off or disconnected during the run, check `residual`
   as soon as it is back.
4. If the harness is interrupted (Ctrl-C, SIGTERM, SIGHUP), it stops the running step
   on the node. If it is killed outright (SIGKILL, power loss), the step may keep
   running on the node until the node is deleted. That costs nothing extra, but its
   output is lost.

**Resuming after a recorded stop.** A run whose `stops.jsonl` has an entry does not
create anything or run test steps again, whatever the cause. It can only be torn
down. To go on testing:
1. tear the run down;
2. confirm `residual` reports nothing left;
3. the Owner approves a **new run id**, with a new approval file and a new state
   directory.

Do not edit or delete `stops.jsonl` to continue a run.

## Approving a run

Only an approval the Owner signed is executed. An approval written by anyone else,
including an AI agent writing down a chat message, has no valid signature and is
refused. Chat approval cannot be accepted: the harness gets no verifiable sender
from the chat, so it cannot tell the Owner's message from text the agent produced.

**Once:** the Owner creates an approval key and the public half is pinned:

```sh
python3 -I acceptance/stage6/hs6_approve.py --setup        # or --setup --sk for a FIDO security key
```

It asks for a passphrase (or a touch of the security key) and prints one public-key
line. That line goes into `OWNER_SIGNING_KEYS` in `hs6.py` and is committed. Do not
add the key to `ssh-agent` or the macOS keychain: then signing would need no
passphrase.

**For each run:** the implementer gives the Owner one command, for example:

```sh
python3 -I acceptance/stage6/hs6_approve.py --run-id h6abc1 --ops init,network,n2,ssh,upload,teardown,residual
```

The Owner runs it in their own terminal. It:
- refuses without a terminal, or in a shell an AI agent runs (`CLAUDECODE` and
  similar variables);
- refuses if the pinned keys are not exactly the Owner's key, if the key is loaded
  in `ssh-agent`, if anything in `acceptance/stage6/` is uncommitted or untracked,
  or if the run id was used before (except for a cleanup-only approval);
- shows the run id, project, zone, account, operations, nodes, limits, validity
  and the harness's SHA-256 and commit;
- asks the Owner to type the run id, then signs with `ssh-keygen -Y sign` (the
  passphrase or the touch);
- writes `~/hagistack-approvals/<run id>.json` and `.json.sig`, mode 600, never
  overwriting, and checks that `hs6.py` accepts the signature.

**What the signature fixes.** The run id, project, zone, account, operations, budget,
hours, validity, nonce and the harness's SHA-256 are all inside the signed bytes:
changing any byte breaks the signature. A signature cannot be moved to another file.
An approval for one run id is refused for any other, and an approval that has started
a run (`init`) is recorded in `~/.config/hagistack-stage6/used-approvals` and cannot
start another. While `OWNER_SIGNING_KEYS` is empty, nothing can be executed.

**What it does not protect against.** The harness and `hs6_approve.py` run as the
same OS user as the implementer. A same-user process can:
- edit and commit `hs6.py` (for example the pinned key) or `hs6_approve.py` (for
  example what it displays before signing);
- call `gcloud` directly, or use the tests' hooks: an approval for an `.invalid`
  account, signed with any key named in `HS6_OWNER_SIGNERS`, makes the unmodified
  harness send its calls to whatever program `HS6_GCLOUD` names. That gives nothing
  beyond calling `gcloud` directly, and the ledger then shows the `.invalid` account.

What makes such a change visible:
- `hs6_approve.py` reads `hs6.py` from its source (never a cached `.pyc`) and refuses
  to sign unless the pinned keys are exactly the Owner's key and the whole
  `acceptance/stage6` directory is committed and unchanged; it shows that directory's
  last commit;
- any change to `hs6.py` changes the SHA-256 inside the signed approval.

So an approval rests on the key's passphrase (or security key) and on the Owner
reviewing the committed changes to `acceptance/stage6/` before signing. Run the tool
as `python3 -I`, from a checkout whose history you have looked at.

**Cleanup is always possible.** `teardown` and `residual` accept an expired
approval and a changed `hs6.py` (with a warning), so a harness fixed after `init`
can still remove the run. For a run id that has been used, `hs6_approve.py` signs
only a cleanup approval (`--ops teardown,residual`).

**Known limit of the approval-file checks.** The checks look at the real path. They
cannot prevent a process of the same OS user from writing a file; the signature is
what makes such a file useless.

**Checks the harness makes on the approval file:**
- it must be a regular file, not a symbolic link, and it is opened without following
  links;
- it must be owned by the user running the harness, have a single hard link, and
  not be writable by group or others. It is re-checked on the open file
  descriptor;
- the directory that actually holds it (its real path) must be the user's own and
  not writable by group or others. A link elsewhere in the spelled path is
  followed, then judged by where it leads;
- it must lie outside the repository and outside the run's state directory, compared
  by device and inode, so letter case and links do not matter.

On a volume mounted with `noowners` (the external SSD is), every file appears owned
by the current user, so the owner check proves nothing there. Keep the approval file
on a volume that records owners, for example in the Owner's home directory.

The same checks apply to `FILE.sig`.

**Who may sign.** Only the Owner, with the key and passphrase that only the Owner
holds. Implementers and automation never write, sign or edit an approval.

A change to `hs6.py` after the approval makes the SHA-256 differ, and the harness then
refuses every operation except cleanup.

## Order the harness enforces

- The network comes before nodes.
- `n3` and `n4` need `n1`.
- `u1` needs `n4` deleted, and absent in GCE, so at most 20 vCPUs run at once.
- Teardown deletes nodes first and the network last. If a node cannot be deleted,
  it stops before touching the network.

## Evidence

The state directory holds:
- `baseline.json`
- `ledger.jsonl` and `ledger.head`
- `operations.log` (every gcloud call)

Keep it on the external SSD. It names cloud resources, so screen it before quoting.
