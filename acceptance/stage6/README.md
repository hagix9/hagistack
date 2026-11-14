# Stage 6 GCE harness (`hs6.py`)

The harness creates and deletes the GCE resources of one stage 6 run of the
own-RPM acceptance (`../ROCKY_OWN_PACKAGING_STAGE6_PLAN_2026-11-12.md`), and runs
commands on those nodes through IAP. It does not install OpenStack by itself. The
per-configuration steps in the plan are run with `hs6.py ssh` and `hs6.py upload`.
`hs6.py download NODE REMOTE NAME` (operation `download`, added in stage 6-5) brings
one file back from a node of the run:
- It is written only to `<state-dir>/downloads/NAME` (mode 0700 directory), and
  never overwrites an existing file.
- It is kept only if its SHA-256 equals the node's `sha256sum` of the remote file.
  A partial or unverified transfer is deleted.
- The remote path must be absolute and plain, and NAME a plain file name.
- Like `ssh` and `upload`, it runs only under the guards (ssh-keys baseline, cost
  and time limits, lock).

**It is dry-run unless the Owner approved the run.** Without an approval file, every
command prints the gcloud calls it would make and calls nothing, not even read-only
gcloud.

## Files

| File | Purpose |
|---|---|
| `hs6.py` | the harness (Python 3.9+, standard library only) |
| `mock_gcloud.py` | a gcloud stand-in for the tests; it contacts nothing and reads no credentials |
| `test_hs6.py` | local tests: `python3 test_hs6.py` (put `TMPDIR` on the external SSD) |
| `hs6_approve.py` | shows a run's conditions (`--show`), records the Owner's approval of them (`--dev-record`), or signs one (format 3) |
| `APPROVAL.template.json` | the shape of a signed (format 3) approval; not valid as it is (it has no signature) |
| `mock_git.py` | a git stand-in for the tests (`HS6_GIT`, test mode only) |
| `run-plan.json` | the run plan: what an approved run may send to, run on and fetch from its nodes |
| `s66-node.sh` | stage 6-6 steps on n1 (build, release checks, nodocs, install, acceptance, evidence) |
| `s66_web.py` | stage 6-6 page checks on n1: Horizon sign-in, logos, every image; one documentation page |
| `test_s66_node.py`, `test_s66_web.py` | local tests of the two node files (control flow, page checks) |

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

1. An approval file (`--approval FILE`, kept outside the repository), either
   - a **development run record** (`format` 4, written by `hs6_approve.py
     --dev-record` after the Owner approved the shown conditions; see "Development
     runs"). It has no signature: the harness checks its contents, not who approved; or
   - a **signed approval** (`format` 3) **and** `FILE.sig`, the Owner's SSH signature
     of exactly that file (see "Approving a run (signed, format 3)"). The signature
     must verify against a key pinned in `OWNER_SIGNING_KEYS` in `hs6.py`, in the
     namespace `hagistack-stage6-approval`.

   Both formats have, and the harness checks:
   - the `format` and a random `nonce`;
   - the run id, project and zone;
   - the gcloud account;
   - the exact `owner_statement` the harness prints for the run;
   - the SHA-256 of this `hs6.py`. Any change to the harness needs a new approval.
   - the full id of the **commit** to run. A non-cleanup operation runs only if the
     checkout's HEAD is that commit and no tracked file is changed (untracked
     files are allowed). `hs6_approve.py` writes the commit only for a checkout
     with no change to a tracked file. What a node gets is fixed by the **run
     plan** of that commit (next section).
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

## The run plan (what a node gets)

`acceptance/stage6/run-plan.json` lists everything an approved run may do on its
nodes.

**How the harness reads the commit.** It reads the plan, and the files it sends,
from the approved commit itself:
- with git's raw objects (`cat-file --batch`), with every object id recomputed
  from its bytes, starting from the commit id;
- with replace objects, system and global configuration, filters, attributes and
  line-ending conversion all off.

So a replace ref, a smudge filter, `core.autocrlf` or a changed working file
cannot change what is read: they either have no effect, or the run stops.

**What the Owner sees.** Before signing, `hs6_approve.py` shows, read the same
way:
- the plan's full SHA-256;
- its nodes;
- every step's full command, and the downloads each step needs first;
- every download with its remote path;
- the full SHA-256 of the tree that will be uploaded.

**What an approval allows.** With an approval, and only then:
- `ssh NODE -- STEP` runs only the plan's command for STEP. The command line is
  the step's name, never a command. `{tree_sha256}` in a command becomes the
  SHA-256 of the tree upload the node verified for this commit. A step may name
  `requires_downloads`: it runs only once those files are kept in `downloads/`.
  A dry-run shows the command the plan at HEAD gives the step.
- `upload NODE @tree REMOTE` sends only the plan's paths of the approved
  commit, to the plan's remote path. The harness builds the tar itself, from
  the verified objects. It is the same bytes on every run (owner root, modes
  0644/0755, the commit's time) and the same as the SHA-256 the Owner was
  shown.
  - The file is written read-only.
  - The upload must hash to the value computed in memory, and the node's
    `sha256sum` must agree.
  - It is then recorded in `tree-upload.json`.
  - No other local file can be uploaded.
- `download NODE REMOTE NAME` fetches only a `NAME -> REMOTE` pair of the plan.
- A node not in the plan's `nodes` gets nothing. A missing or malformed plan
  refuses every ssh/upload/download (cleanup is not affected).

**The stage 6-6 plan.** It uploads `LICENSE`, `rocky10.2/` and the two node
files `s66-node.sh` and `s66_web.py`. Each step is
`s66-node.sh run STEP` (preflight, build, release, nodocs, pack, install, accept,
evidence), after an extract step that checks the tree's SHA-256 again.
- **Steps run as transient system services.** `run` starts the step as a
  service (`systemd-run`, unit `hs6-STEP`), waits for it and prints its log.
  Because the service is not part of the ssh session, a dropped connection or a
  restart of systemd-logind does not kill a long build.
- **`status`** waits until no step runs and prints every step's state and
  results. It is how to get back the result after a dropped connection.
- **Order.** The node script refuses to start a step twice, or before the
  previous one passed. `evidence` needs only that preflight started, so the logs
  of an early failure can be fetched. The plan makes `install` wait until the
  candidate and the build evidence are downloaded.

**What the plan does not fix.**
- What the node fetches itself is pinned elsewhere, not by the plan:
  - upstream tarballs and patches by SHA-256 in the definitions;
  - the build container by digest;
  - the guest image by SHA-256 in the installer.

  Rocky's own packages come from its mirrors, and `build-env.lock` records them.
- The harness runs as the implementer's OS user. A same-user process can call
  `gcloud compute ssh` directly and bypass the harness (see "What it does not
  protect against").

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

## Development runs (format 4: the normal path)

Stage 6-6-R3 made this the path for development GCE runs. It needs no key, no pin and
no signature file.

1. The agent shows the Owner every condition of the run:

   ```sh
   python3 -I acceptance/stage6/hs6_approve.py --show --run-id h6abc1
   ```

   It prints the run id, project, zone, account, operations, the node (machine type,
   disk, image), a list-price estimate, the limits, the commit, the harness's
   SHA-256, the run plan with its SHA-256, the tree's SHA-256, and one **conditions
   SHA-256** over all of them. It writes nothing.
2. The Owner approves those conditions explicitly in chat, naming the run id and the
   conditions SHA-256 (the first 12 digits are enough to name it).
3. Only then, the agent records the approval:

   ```sh
   python3 -I acceptance/stage6/hs6_approve.py --dev-record --run-id h6abc1 \
       --conditions <full conditions sha256> --owner-approval "<where and when the Owner approved>"
   ```

   It recomputes the conditions and refuses, writing nothing, if they differ from the
   approved SHA-256 (another commit, harness, plan, tree, operations, budget or hours).
   It writes `~/hagistack-approvals/<run id>.json` (mode 600, never overwritten) with
   `format` 4, the fixed `authority` text, the Owner's approval note, the plan and
   tree SHA-256 and the conditions SHA-256.
4. The agent runs the harness with `--approval` that file and `HS6_EXECUTE=<run id>`.

**What the harness does not check.** It cannot tell whether the Owner approved: any
process of the same OS user can write a format-4 record, and the same user's gcloud
credentials can call GCE without the harness at all. The record is the agent's
statement that the Owner approved; it is not a proof. This is an operating rule:

- The agent creates, changes or deletes no GCE resource (and runs no `--dev-record`)
  without the Owner's explicit approval of the shown conditions in this run's chat.
  A task instruction that describes a run is not that approval.
- A new run id, a new VM, more time or a higher budget needs a new approval.
- Cleanup (`teardown`, `residual`) of a run that was started is always allowed, also
  after the record expired.

**What the harness still enforces for a format-4 record**, exactly as for format 3:
the run id, project and zone; the commit (HEAD, no changed tracked file) and the
harness's SHA-256; the operations (with `teardown`); budget ≤ US$8 and hours ≤ 6;
validity ≤ 24 h; one run per record (`used-approvals`) and per run id; the run plan
(only its ssh steps, only the commit's tree as the upload, only its downloads, only
its nodes); the cost and time guards; the account and the test-hook refusals. A
record with an `.sig` beside it, another `authority` text or no approval note is
refused. The ledger header records `approval_format`.

## Approving a run (signed, format 3)

Kept from stage 6-6, not required for development runs. While `OWNER_SIGNING_KEYS` is
empty, a format-3 approval cannot be executed. An approval written by anyone else
than the Owner has no valid signature and is refused.

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
- refuses unless started as `python3 -I` (isolated mode: nothing planted next to it
  is imported), without a terminal, or in a shell an AI agent runs (`CLAUDECODE` and
  similar variables);
- refuses if the pinned keys are not exactly the Owner's key, if the key is loaded
  in `ssh-agent`, if anything in `acceptance/stage6/` is uncommitted, untracked or
  ignored by git (a planted `.pyc`, for example), if any tracked file in the
  checkout is changed, if the key file is inside the repository (also refused by
  `--setup`), or if the run id was used before (except for a cleanup-only
  approval);
- shows the run id, project, zone, account, operations, nodes, limits, validity
  and the harness's SHA-256 and commit;
- asks the Owner to type the run id, then signs with `ssh-keygen -Y sign` (the
  passphrase or the touch);
- writes `~/hagistack-approvals/<run id>.json` and `.json.sig`, mode 600, never
  overwriting, and checks that `hs6.py` accepts the signature.

**What the signature fixes.** The run id, project, zone, account, operations, budget,
hours, validity, nonce, the harness's SHA-256 and the commit are all inside the signed bytes:
changing any byte breaks the signature. A signature cannot be moved to another file.
An approval for one run id is refused for any other, and an approval that has started
a run (`init`) is recorded in `~/.config/hagistack-stage6/used-approvals` and cannot
start another. While `OWNER_SIGNING_KEYS` is empty, no format-3 approval can be executed.

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
reviewing the committed changes to `acceptance/stage6/` before signing. The tool
refuses to run without `python3 -I`; run it from a checkout whose history you have
looked at.

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
holds. Implementers and automation never write, sign or edit a format-3 approval
(a format-4 record is written by the agent, under the rule in "Development runs").

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
