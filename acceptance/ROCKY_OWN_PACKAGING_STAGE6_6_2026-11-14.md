# Hagistack's own RPM packaging — stage 6-6: GCE build and acceptance, preparation (2026-11-14)

The implementer wrote this record. The independent audit, run by a separate
agent, is reported in its own section below.

**State: stopped at the Owner gate (Phase 2).** The Owner's approval key is not
set up, so no public key is pinned and no run is signed. Therefore:
- No GCE resource was created, changed, deleted or read.
- No VM was created.
- No RPM was built.
- Nothing was signed.
- Nothing was pushed, tagged or released.

This stage prepared everything that needs no GCE operation.

## Commits

Branch `feat/rocky-own-packaging-s65r1`, after `baa8150`:

| Commit | Change |
|---|---|
| `4467c1d` | the run plan (`run-plan.json`) enforced by `hs6.py` and shown by `hs6_approve.py`; the node steps `s66-node.sh`; the page checks `s66_web.py`; tests |
| `c7d4b06` | audit fixes B1, M1–M5, L1–L7, NV1, NV2 (below) |
| `9ea4b52` | re-audit LOWs L-a, L-b, L-c |
| (this record) | — |

Hygiene:
- The 21 untracked files are unchanged.
- `rocky10.2/packaging/__pycache__/` still has its 15:36 timestamp.
- The original branch is still `ba3395c`.
- The old RPM sets were not touched.
- Files were staged by explicit path only.
- Python ran with `-B` and `PYTHONDONTWRITEBYTECODE=1`.
- Every diff was screened for credentials and personal data (0 hits).

## Phase 0: start audit

| Check | Result |
|---|---|
| HEAD | `baa815004bf4cdae9d8bb2909dba7a0d77677a2e`, as expected |
| Tracked files | no change |
| Untracked | 21, the protected set |
| `.pyc` in history | 0 reachable from any branch (`git log --all`) |
| Old RPM sets | not touched |
| Stage 6-5-R2 implementation | present: notices in `/usr/share/hagistack/changes/`, `mark_files`, `release_check.py notices`, approval format 3 with `commit` |
| Approval harness and key | consistent: format 3, ed25519 or sk-ed25519, namespace `hagistack-stage6-approval`, `OWNER_SIGNING_KEYS` empty, so nothing can execute |
| GCE permissions, quotas and budget | **not checked.** Reading them is a GCE operation and needs the signature. `hs6.py init`, the first signed operation, checks quotas and the image read-only and stops if they do not fit. A budget or alert in Cloud Billing is not visible to the harness |

## Phase 1: approval harness

### 1.1 What the signature covers

| Required | In the signed approval |
|---|---|
| commit (full SHA) | `commit`. A non-cleanup operation needs HEAD equal to it and no change to a tracked file |
| run id | `run_id` |
| operations | `operations` |
| project, zone | `project`, `zone` (must equal the harness constants) |
| machine type | through the commit: `hs6.NODES` (n1 = n2-standard-8, pd-standard 100 GB) and the operation `n1`; `hs6_approve.py` shows it |
| cost limit | `budget_usd` (at most 8) |
| time limit | `max_hours` (at most 6) |
| validity | `approved_at`, `expires_at` (at most 24 h) |
| harness identity | `harness_sha256` of `hs6.py`, and the commit |

The format is unchanged: format 3, the same fields. The `owner_statement` text
still says "Stage 6-1". It is fixed text that the harness compares, so it was
left as it is.

### 1.2 What a node gets: a gap, now closed

**Found.** Before this stage, the harness accepted any command for `ssh` and
any local file for `upload`. The commit binding fixed the harness, not what
reached a node.

**Fix: the run plan** (`acceptance/stage6/run-plan.json`). The approval format
is unchanged.

How the harness reads the plan and the files it sends:
- from the approved commit's raw objects (`git cat-file --batch`);
- with each object id recomputed from its bytes, starting from the commit id;
- with replace objects, system and global configuration, filters, attributes,
  line-ending conversion and lazy fetch all off;
- with a 300 s limit on the git process.

With an approval:

| Operation | Allowed |
|---|---|
| `ssh NODE -- STEP` | only a step of the plan, which runs that step's fixed command. `{tree_sha256}` becomes the SHA-256 of the tree the node verified for this commit |
| `upload NODE @tree REMOTE` | only the plan's paths of the approved commit, as a tar the harness builds itself from the verified objects. It is the same bytes on every run and on Python 3.9 and 3.13, written read-only. It must hash to the in-memory value, and the node's `sha256sum` must agree |
| `download NODE REMOTE NAME` | only a `NAME -> REMOTE` pair of the plan |
| a node not in the plan | nothing |

Other rules:
- `install` waits until the candidate and the build evidence are downloaded.
- A missing or malformed plan refuses ssh, upload and download. Cleanup does
  not use the plan.
- `hs6_approve.py` shows, before signing:
  - the plan's full SHA-256;
  - every step's full command;
  - every download with its remote path;
  - the full SHA-256 of the tree.

**How the chain fixes the inputs:**
1. The signature names the commit.
2. The harness runs only at that commit, with a clean tracked tree.
3. The plan and the tree are read from that commit's verified objects.
4. The node's extract step checks the tree's SHA-256 again before it unpacks.
5. Each step runs `s66-node.sh` from that tree.
6. `s66-node.sh` takes only the step name. The tag, the network ranges and the
   paths are fixed in the file.

A change to the build inputs after the approval stops the run.

**What it does not fix:**
- What the node fetches itself is pinned elsewhere:
  - upstream tarballs and patches by SHA-256 in the definitions;
  - the build container by digest;
  - the CirrOS image by SHA-256.

  Rocky's own packages come from its mirrors, and `build-env.lock` records them.
- A process of the implementer's OS user can call `gcloud` directly (unchanged,
  in the README).
- A step's log reaches the harness's `remote/*.log` without the evidence's secret
  scan. No current step prints a secret.

### 1.3 The Owner's private key

Reviewed in code:
- `--setup` runs `ssh-keygen` locally.
- The key file must be outside the repository.
- Only the public line is printed.
- Signing refuses:
  - without a terminal;
  - in a shell an AI agent runs;
  - while the key is in `ssh-agent`.
- The harness holds public keys only.

Nothing in this stage generates, reads or sends a private key, and nothing signs.

## Node procedure (stage 6-6 plan)

**How each step runs.** Each step is `s66-node.sh run STEP`:
- It starts the step as a transient system service (`systemd-run --unit=hs6-STEP
  --collect --wait`). The service is not part of the ssh session, so a dropped
  connection or a logind restart does not kill a long build.
- It then prints the step's log.

**`status`** waits until no step runs (at most 3.5 h) and prints every step's
state and results.

**Rules on the node:**
- A step starts once.
- A step starts only after the previous one passed.
- A second `run` is refused before any service starts.
- `evidence` runs once `accept` has started, or once a step has failed.

| # | Step | Does | Passes when |
|---|---|---|---|
| 0 | `extract` | unpacks the tree to `/var/tmp/hs6/tree` | the SHA-256 is the recorded one; the directory did not exist |
| 1 | `preflight` | records the tools: rpm, gawk, Python, `%__docdir_path`, SELinux | Rocky 10.2 x86_64, `vmx`, no OpenStack package, no `/var/lib/hagistack`, `%__docdir_path` does not cover `/usr/share/hagistack` |
| 2 | `build` | `hagistack rpm-prepare --rpm-source build`: the pinned container, all definitions | exit 0; identity = SHA-256 of `RPM-SHA256SUMS`; not the old set `6c43da…`; 69 SRPMs; every binary's SOURCERPM is in the set, and every SRPM has a binary |
| 3 | `release` | `make-rpm-release.sh --tag rocky10.2-rpms-2026.1-rc3`, run twice | both exit 0, so every stage 6-4 check plus `notices` and `branding` passes on this set; the two candidates are byte-identical; the lock names the set, its count and the tag; `SHA256SUMS` verify |
| 4 | `nodocs` | the notice RPMs and the documentation RPMs installed into two scratch roots, with and without `--excludedocs` (`--nodeps --noscripts --noplugins`, the host's account files copied in) | one notice per RPM; no `d` flag; every notice in both roots, byte-identical; 0 files under `/usr/share/doc` with nodocs, more than 0 without; `HAGISTACK-LICENSE` kept; the marked files are the same in both; marked `.py` files compile, `.sh` files parse, and no mark sits above a shebang |
| 5 | `pack` | `candidate.tar` and `evidence-build.tar` in `/var/tmp/hs6-dl` | written; their SHA-256 printed |
| — | `download` ×2 | both, verified by SHA-256, before any install | — |
| 6 | `install` | `hagistack all-in-one --rpm-source build`, which reuses the verified set; a dummy `hgext0` | exit 0; the deployment records the new set, not the old one; every installed package named in the set has the set's `SHA256HEADER`; no novnc |
| 7 | `accept` | below | below |
| 8 | `evidence` | `evidence-final.tar`, with the build's logs | no value of a password, secret, token or key in `/etc/hagistack`, no Horizon secret key, no private key, no Keystone token |
| — | `download` | verified | — |

`accept`, before and after a restart of every OpenStack, OVN, Open vSwitch,
libvirt and httpd unit:
- **APIs:** the Keystone token; the Nova API; scheduler, conductor and compute up;
  the Neutron API; agents alive; Placement lists a resource provider; a
  hypervisor up. Each waits up to 120–300 s.
- **`tests-horizon-login.sh`.**
- **`s66_web.py horizon`:**
  - signs in;
  - loads the login page, `/admin/`, `/admin/hypervisors/` and
    `/project/instances/`;
  - fetches every image, stylesheet, script, icon, `srcset`, `<style>`, `style=`,
    `@import` and `url()` they name; each must be HTTP 200;
  - an image from another host fails;
  - every served `logo.svg`, `logo-splash.svg`, `favicon.ico`,
    `apple-touch-icon.png` and `safari-pinned-tab.svg` must be Hagistack's
    bytes;
  - the first three must each be loaded by some page.
- **Before the restart only:**
  - **Documentation.** One documentation RPM of the set is installed with `dnf`
    (`tsflags` cleared) and served over HTTP. Its index page and everything the
    page loads must be HTTP 200. Every theme logo and favicon path under
    `_static/` must serve Hagistack's bytes.
  - **Guests.** Two CirrOS guests boot ACTIVE. SSH works with the injected key, the
    metadata `instance-id` is read, and the first pings the second (3/5 at
    least).
- **After the restart:** a third guest, 0 failed units, the header check again, and
  the number of tracebacks.

**Off the node, after the download:** regenerate the 69 specs at the approved
commit and compare them with the specs inside the SRPMs ("54 changed, 15
unchanged" against the real build).

**Not checked:**
- what a browser renders;
- SELinux enforcing, floating-IP reachability from outside, live migration,
  `%check`;
- the Google Cloud bill.

**Failure handling.** A failed step stops progress. No retry and no new VM
without a new approval. Then `evidence`, `download`, `teardown`, `residual`.

## Cost and time (n1 only)

At list prices, from the harness's constants:
- the VM: US$0.498/h;
- the 100 GB pd-standard disk: about US$0.007/h;
- the NAT gateway and its IP: US$0.0064/h;
- NAT data, assumed 10 GiB: US$0.45;
- egress, assumed 0.5 GiB: US$0.10. The candidate is about 160 MB.

| Case | Estimate |
|---|---|
| planned 4 h | about US$2.6 |
| harness limit 6 h | about US$3.6 |

How the limits are enforced:
- The harness tears down at US$8 accrued or 6 h.
- It creates nothing new at US$7 projected.
- GCE deletes n1 at its maximum run duration.

The harness estimates cost; it cannot read the bill.

Time, from earlier runs:
- build about 35–46 min;
- release about 10 min ×2;
- install about 9 min.

The total is expected around 2–3 h. The time is not well known: the documentation
builds are new.

## Tests (local)

| Suite | Python 3.13 | Python 3.9 |
|---|---|---|
| `test_hs6.py` + `test_s66_web.py` + `test_s66_node.py`, at `9ea4b52` | **207 OK** | **207 OK** (3.9.6) |
| `bash -n s66-node.sh` (local bash 3.2; bash 5 not available here) | OK | — |

The new tests cover:
- **Plan enforcement:** commands, uploads, downloads and nodes outside the plan;
  the tree SHA-256 placeholder; `requires_downloads`; malformed plans; a missing
  plan; the dry-run preview.
- **Commit content:** a replace ref, a smudge filter, attributes, `autocrlf`, the
  working tree, a corrupt object, a symbolic link, a missing path, and the same
  archive bytes on 3.9 and 3.13.
- **Node control flow:** order, once only, `run`, `status`, evidence timing, a
  refused rerun.
- **The secret scan.**
- **The page checks:** a stand-in Horizon and documentation server.

Self-review findings, fixed before the first audit:
- a start refused for order used up the step;
- `rpm -qlp | grep -q` under `pipefail`;
- a test placed outside `check`;
- `bash -c` losing variables;
- an implicit `join` key.

One run of the Python 3.9 suite before the audit showed one failure. It was not
reproduced in a rerun (168/168), and its details were not kept: **cause unknown**.

## Independent audit

**First audit** (separate agent, of `4467c1d`): **NO-GO.**
- **B1.** `git show` and `git archive` follow local git state: replace refs,
  `.git/info/attributes` with a filter, `core.autocrlf`. With `git status`
  clean, the plan and the node script could be swapped, and the Owner's display
  would show the swapped plan. Reproduced by the auditor.
- **M1.** Long steps ran in the ssh session. A dropped connection would kill the
  step and use up its once-only start.
- **M2.** There was no way to fetch logs after an early failure.
- **M3.** The Owner did not see commands, remote paths or the tree SHA-256.
- **M4.** The upload file could be swapped between building and hashing.
- **M5.** The tests did not use real git objects.
- **LOW L1–L7, NOT VERIFIED NV1–NV4.**

All were fixed in `c7d4b06`, as described above.

**Re-audit** (same agent, of `c7d4b06`): **GO**, 0 BLOCKER/HIGH/MEDIUM.
- It repeated the B1 reproductions against the new code. All were defeated, and
  a corrupt object stops the run.
- The tree is byte-identical on Python 3.9 and 3.13.
- New LOWs:
  - **L-a.** A refused rerun was reported as PASSED.
  - **L-b.** Evidence taken too early loses the final evidence.
  - **L-c.** The git read had no timeout or lazy-fetch guard.
  - **L-d.** Step logs bypass the secret scan. This is recorded under "What it
    does not fix".

  L-a to L-c were fixed in `9ea4b52`, and covered by tests.
- **Not verified (do not block; a miss could cost the signed run):**
  - systemd-run under SELinux with podman, dnf and `ip netns`;
  - sysusers in a scratch root;
  - the documentation theme's external images;
  - the step bodies themselves, which only the node run tests.

## Values for the Owner (at `9ea4b52`)

Pinning the key changes only `hs6.py`, which is not in the tree. These values
therefore stay the same in the pin commit. `hs6_approve.py` prints them again
before signing.

| Item | Value |
|---|---|
| run plan SHA-256 | `58459f5233a79a67f5ee554a07e3e53b9a0211cedfccb612fe4e3ed3619ee429` |
| tree SHA-256 | `a8cd1ba6d11ade46b8040378e11d6700726c1c92f60bd7bbe319e8965662a8fe` (1,300,480 bytes; `LICENSE`, `rocky10.2/`, `s66-node.sh`, `s66_web.py`) |
| operations | `init,network,n1,ssh,upload,download,teardown,residual` |
| node | n1: n2-standard-8, pd-standard 100 GB, Rocky Linux 10 family image (10.2 checked by preflight) |
| limits | US$8, 6 h, approval valid at most 24 h |
| release tag of the candidate | `rocky10.2-rpms-2026.1-rc3` (local candidate only; not published) |

## Owner steps

1. **Key, once.** In your own terminal:
   `python3 -I acceptance/stage6/hs6_approve.py --setup` (or `--setup --sk`).
   Send only the printed public line. It is pinned in `OWNER_SIGNING_KEYS` by a
   commit, which is tested and reviewed. You then get its SHA.
2. **Run, after reviewing that commit.** Run
   `python3 -I acceptance/stage6/hs6_approve.py --run-id <rid> --ops init,network,n1,ssh,upload,download,teardown,residual`.
   Check that the plan and tree SHA-256 it shows are the values above, then type
   the run id to sign.

Approving the pin and signing the run are separate decisions.
