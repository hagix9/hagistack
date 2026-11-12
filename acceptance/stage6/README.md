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
| `APPROVAL.template.json` | the shape of an Owner approval; not valid as it is |

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

1. An approval file (`--approval FILE`, kept outside the repository) with:
   - `format` 1;
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
4. No test hook. `HS6_GCLOUD` and `HS6_NOW` work only with an approval whose account
   is in the reserved `.invalid` domain, as in the tests. With a real account they are
   refused.

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
| 6 h since the first creation | stop |
| a node over its planned hours by more than 50 % | stop |
| the monitor cannot compute | stop |

Teardown is always allowed. GCE itself puts no cap on billing. The
`--max-run-duration` on each node is the server-side backstop for nodes. The network
and NAT have no such backstop: the NAT IP costs about US$0.005 per hour while it is
left.

The harness cannot prove who wrote an approval file. It is a procedural control:
- writing the file is the Owner's act;
- implementers and automation must never write one;
- keep the file outside the repository, in a place only the Owner writes to.

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
