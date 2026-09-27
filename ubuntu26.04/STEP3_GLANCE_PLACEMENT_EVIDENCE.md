# Step 3 — Glance and Placement: packaging evidence and verification

- Date: 2026-09-27
- Subject: `ubuntu26.04/hagistack` version `0.3.0-step3`
- Scope: Glance and Placement only. **No Neutron/OVN, Nova, Horizon or compute-add.**
- Environment: `ubuntu:26.04` → **Ubuntu 26.04.1 LTS amd64**, nerdctl/containerd in an
  already-running lima VM. **No systemd in the container.** `/src` read-only.
  No GCE, AWS or Sinter operation; no macOS host service or network change.

## 1. Two different startup models — measured, not assumed

Keystone's answer did not generalise, and the two new services do not match each other.
Everything below came from installing the real packages in a clean Ubuntu 26.04 container.

| | Glance `2:32.0.0-0ubuntu1` | Placement `1:15.0.0-0ubuntu1` |
|---|---|---|
| systemd unit | **`/usr/lib/systemd/system/glance-api.service`** — its own unit, `User=glance`, `ExecStart=/etc/init.d/glance-api systemd-start` | **none.** `dpkg -L placement-api` lists exactly two files |
| Apache vhost | **none** | **`/etc/apache2/sites-available/placement-api.conf`**, already symlinked into `sites-enabled` after install |
| Listen | `#bind_host = 0.0.0.0`, **`#bind_port = <None>`** — no default, must be set | vhost carries `Listen 8778` + `<VirtualHost *:8778>` → `/usr/bin/placement-api` |
| Config owner | **`glance-common`** → `/etc/glance/glance-api.conf`, `0640 root:glance` | **`placement-common`** → `/etc/placement/placement.conf`, `0640 root:placement` |
| Shipped DB | `sqlite:////var/lib/glance/glance.sqlite` | `sqlite:////var/lib/placement/placement.sqlite` |
| DB config key | `[database] connection` | **`[placement_database] connection`** — *not* `[database]` |
| Migration | `glance-manage db_sync` (both `db_sync` and `db sync` accepted) | **`placement-manage db sync`** — `db_sync` is **not** a valid subcommand |
| Store | multi-backend: `[DEFAULT] enabled_backends`, `[glance_store] default_backend`, `[file] filesystem_store_datadir`; `/var/lib/glance/images` exists `glance:glance 0750` | — |

**Decisions.** Glance is driven through **`glance-api.service`**; no vhost is written, because the
package ships none. Placement is driven through **`apache2.service`** using the package's own
vhost — a second vhost on 8778 beside Keystone's 5000 — so the phase reloads the existing server
rather than starting another. No unit name is invented and no uwsgi is installed.

Four things the evidence caught that a guess would have got wrong:

1. `bind_port` has **no default**; Glance would simply not listen on 9292.
2. Placement's connection lives under **`[placement_database]`**; writing `[database]` leaves it on sqlite.
3. The two `db sync` spellings genuinely differ.
4. Package file ownership is `root:glance` / `root:placement` — preserved, not chowned to a service user.

## 2. What the phases do

Both follow the Step 2 contract. Dependencies are gated (MariaDB reachable, the database exists,
Keystone answering, **memcached listening**); an unmet dependency is `note_skip` + exit 4, never a
completion banner. Configuration is written with the idempotent `ini_set`. Migrations run as the
service user with diagnostics redacted. Identity registration is **`show || create`** throughout —
`ks_ensure_user` / `ks_ensure_service` / `ks_ensure_endpoint` reuse what exists and never delete or
recreate; an endpoint whose URL disagrees is **reported and left alone**. Each phase is marked done
only after its API answers an authenticated request.

## 3. Defects this verification found and fixed

| # | Defect | Why it mattered | Fix |
|---|---|---|---|
| 1 | **MariaDB `max_connections` left at the stock 151** | An all-in-one runs Keystone, Glance and Placement pools against one server. Measured: Keystone returned HTTP 500 with `(pymysql.err.OperationalError) (1040, 'Too many connections')`, which broke token validation for Glance. Gets worse as Nova/Neutron arrive | `phase_database` writes `max_connections` (default 1024, overridable) and restarts MariaDB when a server setting actually changed — under systemd only, warning otherwise |
| 2 | `memcached_servers` written unconditionally | A configured-but-dead token cache makes **every** token validation block. Measured: an authenticated placement request timed out after 15 s with 0 bytes | both phases now **gate on memcached being reachable** and refuse to configure against a dead cache |
| 3 | (self-inflicted, then reverted) making that setting conditional on a probe | It made the written config depend on transient state, so `glance-api.conf` and `placement.conf` **changed between runs** — idempotence lost | config is written unconditionally; the *phase* gates instead |
| 4 | (self-inflicted, then reverted) capping each service's client pool | Unmeasured "safety" change; cut `max_overflow` from oslo.db's 50 to 10 and the next run regressed to Apache 503/500 with registration never completing | reverted; only the evidenced server-side fix kept |
| 5 | the memcached probe exchanged data (`version\r\nquit\r\n`) | racy | plain TCP connect |

Items 3 and 4 are worth recording as mistakes: twice I added an unmeasured change on top of an
evidenced one and made things worse (55→43 PASS on item 4). The rule that worked: **change what the
evidence names, and nothing else.**

### Test faults found — including one that nearly reported false data loss

- **A mis-quoted verification query.** The third-run check queried
  `... WHERE name='hagistack-test'` through mangled nested quoting, returned empty, and the harness
  concluded *"image genuinely lost"*. Glance's own log disproved it —
  `"GET /v2/images?name=hagistack-test" 200 1228` — and the on-disk bytes were unchanged. The query
  now lists all rows with no nested quotes. The verdict logic requires three independent signals
  (API, DB row, stored bytes) before calling anything lost.
- **Vacuous stability checks** are prevented by the `digest_of`/`stable` helpers carried over from
  Step 2: a missing artefact returns the literal `ABSENT` and **fails** rather than comparing equal
  to another missing artefact.
- **A `sed` range that ran to EOF.** The Step 1 suite extracted `SECRET_KEYS` with a terminator of
  `/METADATA_PROXY_SECRET"$/`. Adding two service credentials moved that key off the last line, so
  the range swallowed **1196 lines to EOF**, the extracted sub-test never created `secrets.env`, and
  seven secret assertions failed on a file that was never written. Now terminated on the first line
  closing the quote.
- **Pinned step literals** (`0.2.0-step2`, an exact "missing services" sentence, a help phrase that
  now line-wraps). All four suites now assert patterns; a sweep confirms no pinned version strings
  remain, so Step 4 will not repeat this.

## 4. Results

### Step 3 suite — 55 PASS / 0 FAIL / 3 UNVERIFIED (guest exit 0)

Nothing in the container has systemd, so each backing service was started by hand and recorded:

```
MARIADB=mariadbd-safe --bind-address=127.0.0.1 --max-connections=1024 (manual, no systemd)
MEMCACHED=memcached -u memcache -l 10.4.0.55 -d (manual, no systemd)
APACHE=apachectl -k start (manual, no systemd)
GLANCE=glance-api as the glance user (manual, no systemd)
WSGI=processes 5 -> 2 on both vhosts (container tuning, not a product change)
```

| ID | Status | Detail |
|---|---|---|
| `G0a-bash-n` | PASS | parses |
| `G0b-shellcheck` | PASS | no warnings (-S warning) |
| `G0c-version` | PASS | 0.3.0-step3 |
| `G0d-status-lists` | PASS | status lists glance and placement |
| `G0e-status-honest` | PASS | status still says what is missing |
| `G0f-help-honest` | PASS | help still disallows 'working OpenStack' |
| `G1a-exit4` | PASS | exit 4 with no DB |
| `G1b-glance-skip` | PASS | glance skip reported |
| `G1c-placement-skip` | PASS | placement skip reported |
| `G1d-glance-no-marker` | PASS | no state marker |
| `G1d-placement-no-marker` | PASS | no state marker |
| `G1e-no-false-complete` | PASS | did not claim COMPLETE |
| `G2a-mariadb` | PASS | started via: mariadbd-safe --bind-address=127.0.0.1 --max-connections=1024 (manual, no systemd) |
| `G2a2-memcached` | PASS | token cache listening on 10.4.0.55:11211 (started via: memcached -u memcache -l 10.4.0.55 -d (manual, no systemd)) |
| `G2b-mariadb-tcp` | PASS | TCP 3306 listening |
| `G2b2-max-conn` | PASS | server max_connections=1024 (stock 151 caused HTTP 500) |
| `G2c-keystone-up` | PASS | identity answering (started via: apachectl -k start (manual, no systemd)) |
| `G3a-glance-schema` | PASS | 16 tables in the glance schema |
| `G3b-glance-conn` | PASS | connection points at MariaDB |
| `G3c-no-sqlite` | PASS | sqlite default replaced |
| `G3d-glance-perms` | PASS | glance-api.conf 640 root:glance (package ownership preserved) |
| `G3e0-maxconn-written` | PASS | phase_database wrote max_connections into its own conf |
| `G3e-bind-port` | PASS | bind_port explicitly 9292 (no default exists) |
| `G3f-glance-serving` | PASS | image API answers on :9292 (started via: glance-api as the glance user (manual, no systemd)) |
| `G3g-image-list` | PASS | openstack image list succeeded as admin |
| `G3h-catalogue-glance` | PASS | glance present in the service catalogue |
| `G3i-glance-endpoints` | PASS | 3 glance endpoints registered |
| `G4a-image-upload` | PASS | image created id=0e1e4f82-0b0b-4838-9f81-20422a003d38 |
| `G4b-image-on-disk` | PASS | image file present under /var/lib/glance/images |
| `G4c-content-matches` | PASS | stored bytes match the uploaded file (sha256) |
| `G5a-placement-schema` | PASS | 13 tables in the placement schema |
| `G5b-placement-conn` | PASS | connection under [placement_database] points at MariaDB |
| `G5c-right-section` | PASS | nothing written to the wrong [database] section |
| `G5d-placement-perms` | PASS | placement.conf 640 root:placement |
| `G5e-placement-serving` | PASS | placement answers on :8778 via apache2 (same server as identity) |
| `G5f-placement-auth` | PASS | authenticated /resource_providers -> HTTP 200 |
| `G5g-placement-body` | PASS | response body has resource_providers (empty is correct; Nova not installed) |
| `G5h-placement-endpoints` | PASS | 3 placement endpoints registered |
| `G5i-nova-rp` | UNVERIFIED | Nova resource-provider registration: not required in step 3 |
| `G6a-glance-conf` | PASS | glance-api.conf unchanged (d100011a07811631b0d54d274e8105d96c0487723078796ee0d0d2fb58fbca77) |
| `G6b-placement-conf` | PASS | placement.conf unchanged (530d70bb593584c43d085a61757cb3bff72434d2527b348fe297e8386ba42c34) |
| `G6c-secrets` | PASS | secrets.env unchanged (d9721b7ec51a2f519223ac3bcbe1668bac674a3332cfe2dd8cd0b943492ebfce) |
| `G6d-glance-tables` | PASS | glance table count unchanged (16) |
| `G6e-placement-tables` | PASS | placement table count unchanged (13) |
| `G6f-glance-user-id` | PASS | glance service-user id unchanged (2) |
| `G6g-endpoint-count` | PASS | endpoint count unchanged (9) |
| `G6h-conf-reported` | PASS | re-run reports configs unchanged |
| `G6i-schema-reported` | PASS | re-run reports schema current |
| `G6j-reuse-reported` | PASS | re-run reports existing users/services reused |
| `G6k-image-id` | PASS | image id unchanged (0e1e4f82-0b0b-4838-9f81-20422a003d38) |
| `G6l-image-cksum` | PASS | image checksum unchanged (ede58fa138a85202602f0fade982ef54) |
| `G6m-image-content` | PASS | stored image bytes unchanged (2b65a9ead4cc5e578b85514ec5b96f5c87b831b09a4cf769c1a1cf585ec96e07) |
| `G6n-third-run` | PASS | image still present after a 3rd run |
| `G6o-image-content-3rd` | PASS | stored image bytes after 3 runs unchanged (2b65a9ead4cc5e578b85514ec5b96f5c87b831b09a4cf769c1a1cf585ec96e07) |
| `G7a-no-secret-in-log` | PASS | no secret value appears in any run output |
| `G7b-no-pass-in-argv` | PASS | service password not in process args |
| `G7c-systemd-startup` | UNVERIFIED | glance-api.service / apache2.service under systemd: GCE (B0a/B0b) |
| `G7d-real-accept` | UNVERIFIED | Neutron/OVN, Nova, Horizon and instance boot: not in step 3 |

### Regression on the same build

| Suite | Result | Guest exit |
|---|---|---|
| `container-audit.sh` (Step 1) | **40 PASS / 0 FAIL / 0 UNVERIFIED** | 0 |
| `container-verify.sh` (Step 1) | **65 PASS / 0 FAIL / 6 UNVERIFIED** | 0 |
| `container-dbtest.sh` (Step 1) | **28 PASS / 0 FAIL / 3 UNVERIFIED** | 0 |
| `container-step2.sh` (Keystone) | **51 PASS / 0 FAIL / 2 UNVERIFIED** | 0 |
| `container-step3.sh` (Glance + Placement) | **55 PASS / 0 FAIL / 3 UNVERIFIED** | 0 |

## 5. API responses and image retention

```
image API   : answers on :9292; `openstack image list` succeeds as admin
              glance in the catalogue; 3 endpoints registered
placement   : answers on :8778 via the same apache2 that serves identity
              authenticated GET /resource_providers -> HTTP 200
              body has resource_providers (empty is correct — Nova is not installed)
              3 endpoints registered
```

A 64 KB random test image was uploaded and tracked by three independent signals:

```
run 1:  id 0e1e4f82-0b0b-4838-9f81-20422a003d38, stored bytes == source sha256
run 2:  id unchanged; glance checksum unchanged ede58fa138a85202602f0fade982ef54
        stored bytes unchanged 2b65a9ead4cc5e578b85514ec5b96f5c87b831b09a4cf769c1a1cf585ec96e07
run 3:  image still present; stored bytes still unchanged
```

Corroborated straight from MariaDB: `0e1e4f82-…  hagistack-test  active`.

Everything else preserved across re-runs: both configs byte-identical, `secrets.env` unchanged,
glance 16 tables and placement 13 tables unchanged, the **glance service-user id unchanged** (proving
`show || create` reused rather than recreated), endpoint count steady at 9. No secret value appears
in any run output, and no service password appears in process arguments.

## 6. Still not verified

| Item | Why | Goes to |
|---|---|---|
| `glance-api.service` and `apache2.service` **under systemd**, unit ordering | no systemd in a container; every service was started by hand | GCE 区分 B — B0a / B0b |
| Nova resource-provider registration in Placement | out of scope for step 3 | a later step |
| Neutron/OVN, Nova, Horizon; creating a network; booting an instance | not implemented | later steps, then GCE |
| Physical LAN, provider network, Floating IP | not implemented | GCE 区分 B / C |

Nothing here has run on real Ubuntu 26.04 hardware or on a GCE VM. **`all-in-one` at this stage gives
base services, identity, image and placement — it is not a usable cloud**, and the banner, `--help`
and `status` all say so.
