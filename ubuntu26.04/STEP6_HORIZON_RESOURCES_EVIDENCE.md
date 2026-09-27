# Step 6 — Horizon, the initial resources, and `compute-add`

Base: branch `docs/openstack-renewal-research`, on top of `472493e` (step 5).

Three things land here, and one wording problem gets fixed. The wording problem
first, because it is the one that was actively misleading.

---

## 0. The stale header, and the claim this shell is now careful about

`ubuntu26.04/hagistack` still opened with:

```
# STATUS: STEP 1 of the rebuild. Skeleton + preflight + base services only
#         (MariaDB, RabbitMQ, memcached). Keystone, Glance, Placement, Nova,
#         Neutron/OVN and Horizon are NOT implemented yet ...
```

By step 5 every service named there except Horizon *was* implemented, so the
first thing anyone read about the file was false. It is gone.

What replaced it is not just an updated list. The file now keeps two claims
apart everywhere it reports anything:

* **IMPLEMENTED** — the code exists here and runs.
* **VERIFIED** — observed working on a real machine.

They are carried as two separate strings (`IMPLEMENTED_PHASES` /
`COMPUTE_ADD_PHASES` and `VERIFIED_ON_HARDWARE` + `UNVERIFIED_ITEMS`), and the
header, `--help`, `status` and the closing banner all print both. Today the
second one reads:

```
verified on hardware    : none — no Ubuntu 26.04 host and no GCE VM has ever run this
still unverified        : Horizon login; guest boot; compute-add Placement
                          registration; OVN chassis; node-to-node Geneve;
                          any physical-LAN path
```

The step 6 suite asserts this rather than trusting it: `S0d` requires both
labels to appear, `S0e` requires the hardware line to say `none`, `S0g` requires
`status` to say the dashboard login is untested, and `S0k` fails the build if any
unqualified "usable OpenStack" / "production-ready" phrase appears anywhere in
the file.

---

## 1. Horizon: packaging facts, measured

`openstack-dashboard` **4:25.7.1-0ubuntu1**, measured by unpacking the `.deb`
files rather than installing them (the guest had ~1.5 GB free).

| Fact | Why it matters |
|---|---|
| `openstack-dashboard` ships **exactly one** file: `/etc/apache2/**conf-available**/openstack-dashboard.conf` | It is a **server-wide fragment, not a vhost**. It carries no `Listen`. Horizon is served by whatever vhost already exists — in practice the packaged default site on **port 80** — at the path `/horizon`. Because it is server-wide, that alias is inherited by the identity/placement/neutron/nova vhosts too. hagistack does not fight the packaging over this; it says so, and `curl`s port 80. |
| postinst runs `apache2_invoke enconf` | the fragment is enabled on install; `a2enconf` is re-asserted, not assumed |
| postinst runs `collectstatic` **and** `compress --force` | `COMPRESS_OFFLINE = True` is set in the shipped settings, so missing offline assets show up as HTTP 500, not as an ugly page |
| postinst runs **`invoke-rc.d memcached restart`** | installing the dashboard **bounces the token cache the other services use**. The phase warns before installing and re-checks memcached afterwards. |
| settings live in `/etc/openstack-dashboard/local_settings.py`, a dpkg **conffile**, symlinked to `…/openstack_dashboard/local/local_settings.py` | editing it means a dpkg prompt on every upgrade |
| `openstack_dashboard/settings.py` line ~264 `exec`s every `*.py` in `…/openstack_dashboard/local/local_settings.d/`, **after** importing `local_settings.py` | a snippet there overrides the conffile without touching it. That is where hagistack writes, as `_99_hagistack.py`. |
| that loader is wrapped in `except Exception: _LOG.exception(...)` | **a broken snippet is silent.** Horizon keeps the packaged defaults and nothing says so. |
| shipped defaults are `OPENSTACK_KEYSTONE_URL = "http://127.0.0.1/identity/v3"` (a DevStack path) and cache `LOCATION = 127.0.0.1:11211` | both wrong here — hagistack binds memcached to the management address, and identity is on `:5000/v3`. Both are overridden. |
| `SESSION_ENGINE = 'django.contrib.sessions.backends.cache'` | Horizon keeps **sessions** in memcached. A dead cache is not a slow dashboard, it is a dashboard nobody can log into. The phase refuses to configure against one. |
| `python3-pymemcache` is **not** a dependency of `python3-django-horizon`; it arrives via `python3-django-openstack-auth` | checked with `apt-get install -s openstack-dashboard`, which does pull it (and `memcached`). No extra package is installed. |
| `/usr/share/openstack-dashboard/manage.py` comes from `openstack-dashboard-common` | that is the path used if static assets ever need regenerating |

### 1.1 The consequence of the silent loader

Because a bad snippet fails without a trace, the phase does not trust the file
it just wrote. It asks Django what the settings actually are:

```
python3 -  <<'PYEOF'
sys.path.insert(0, "/usr/share/openstack-dashboard")
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "openstack_dashboard.settings")
from django.conf import settings
print("KEYSTONE_URL=%s" % settings.OPENSTACK_KEYSTONE_URL)
print("CACHE_LOCATION=%s" % settings.CACHES["default"]["LOCATION"])
print("SESSION_ENGINE=%s" % settings.SESSION_ENGINE)
PYEOF
```

and compares the two values it set against what came back. A mismatch is a
skipped phase with the reason, not a success.

### 1.2 What the phase deliberately does not do

* **It does not narrow `ALLOWED_HOSTS`.** The package ships `['*']`. Narrowing it
  would break reaching the dashboard through an address this host does not know
  about — a cloud external IP, or an SSH tunnel, which is exactly how the GCE
  acceptance will reach it. The snippet says so in a comment rather than
  silently leaving it out.
* **It does not re-run `collectstatic`/`compress` on every run.** They cost
  minutes. They run only when `/var/lib/openstack-dashboard/static` is empty.
* **It does not install `nova-novncproxy`.** The console tab in Horizon will
  therefore not work. That is a stated gap, not an oversight.

### 1.3 What is proven, and what is not

Proven by the phase, at run time: the settings took effect, and
`http://$MGMT_IP/horizon/auth/login/` answers **200**.

Not proven by anything: that a login succeeds. A served page is not a session.
The phase says this in a warning, `status` prints `login tested   NO — never, by
anyone`, and the suite asserts that it does.

---

## 2. The initial resources

The smallest set an instance needs. Everything is show-or-create by name;
nothing is ever deleted or recreated (asserted by `S6a`, which fails the build
if any `openstack … delete` appears in the file at all).

| Resource | Name | Notes |
|---|---|---|
| flavor | `m1.tiny` | 1 vCPU / 512 MiB / 1 GiB. The cirros image's virtual size is 112 MiB, so it fits |
| image | `cirros-0.6.3-<arch>` | see §2.1 |
| external network | `hagistack-provider` | flat on `$PROVIDER_PHYSNET`, `--external --share` |
| its subnet | `hagistack-provider-subnet` | `$PROVIDER_CIDR`, **`--no-dhcp`** — those addresses are handed out as floating IPs, not leased |
| tenant network | `hagistack-tenant` | geneve, per `ml2 tenant_network_types` |
| its subnet | `hagistack-tenant-subnet` | `$TENANT_CIDR`, `--dns-nameserver $DNS_SERVER` |
| router | `hagistack-router` | external gateway + an interface on the tenant subnet |
| security group rules | on the admin project's `default` group | ICMP and TCP/22 from `0.0.0.0/0` |
| keypair | `hagistack-key` | RSA 3072 at `/etc/hagistack/hagistack-key`, mode 0600 |

The `hagistack-` prefix is not decoration: it means these names cannot collide
with, or be confused for, anything an operator made.

Two idempotence details that are easy to get wrong:

* **Security group rules.** Neutron answers a duplicate rule with **409
  Conflict** rather than accepting it. That is used as the idempotence signal:
  create, and treat "already exists / conflict / 409" as success. Anything else
  is an error.
* **Router interface.** `router add subnet` on an already-attached subnet says
  "Router already has a port on subnet". Same treatment.

**RSA, not ed25519, for the keypair.** The private key has to work against
whatever small SSH server the guest image runs; RSA is the one algorithm every
one of them accepts. This is a compatibility choice and it is written down as
one.

### 2.1 The image, and why a test image is not an initial image

There is **no cirros package in the Ubuntu archive** — `apt-cache policy cirros`
and `cirros-testvm` both return no candidate. So the image has to come from a
URL or a file.

The default URL and digest were **measured on 2026-09-27**, not copied from a
tutorial:

```
curl -sS https://download.cirros-cloud.net/0.6.3/SHA256SUMS
  7d6355852aeb6dbcd191bcda7cd74f1536cfe5cbf8a10495a7283a8396e4b75b  cirros-0.6.3-x86_64-disk.img
  611879b8299363fe60ff0f84982e4da08e63f476e8481170223db982959783cb  cirros-0.6.3-aarch64-disk.img

curl -sSL .../cirros-0.6.3-x86_64-disk.img -o c.img
  21692416 bytes
  shasum -a 256 c.img
  7d6355852aeb6dbcd191bcda7cd74f1536cfe5cbf8a10495a7283a8396e4b75b   <- matches
  file c.img -> QEMU QCOW2 Image (v3), 117440512 bytes
```

Two things that came out of doing it rather than assuming it:

1. **The download URL answers 302.** Without `curl -L` the saved file is a
   **273-byte redirect page**. The shell uses `-fsSL`, and the comment in the
   source says why.
2. The virtual size is 112 MiB, which is what sets `m1.tiny`'s 1 GiB disk.

The rules around it:

* **A URL is never fetched without a digest.** `--image-url` without
  `--image-sha256` is a preflight error, with instructions for getting the
  publisher's digest.
* The file is verified **before** it reaches Glance. A mismatch is refused and
  the file is left on disk for inspection — never uploaded, never silently
  replaced.
* A cached file that already matches is not downloaded again.

**The step 3 test image is not the initial image.** An image hagistack uploads
carries a property `hagistack_sha256=<the pinned digest>`. On a re-run:

| Found | Action |
|---|---|
| name matches, property matches, status `active` | reused, untouched |
| name matches, **no** `hagistack_sha256` property | **refused.** hagistack did not upload it, so it is not treated as the initial image — and it is not modified or deleted either. The message says to pick another `--image-name` or remove that image by hand. |
| name matches, property differs | same refusal |

That is exactly the case of a throwaway image left behind by a verification run
sharing a name: it is never promoted to "the production initial image", and it
is never destroyed to make room.

---

## 3. `compute-add`

### 3.1 What a compute node deliberately does not get

| Not given | Why |
|---|---|
| any **database** credential | since Pike a compute node must not reach the cell database; it goes through `nova-conductor` over RabbitMQ. `S6f` fails the build if `phase_compute_nova` ever writes a `[database]` or `[api_database]` connection. |
| the **admin** password | nothing on a compute node authenticates as admin |
| `ovn-bridge-mappings` | a mapping with no NIC behind it invites OVN to bind a provider port to this chassis and drop its traffic. Tenant (geneve) ports need no mapping. Add one by hand once a real NIC is attached. |
| `enable-chassis-as-gw` | the controller is the gateway chassis. `S6g` asserts this. |

### 3.2 How the secrets get there

Explicitly, by the operator, and never generated locally — a compute node that
invented its own RabbitMQ password would simply fail to talk to anything.

```
controller:  sudo hagistack compute-secrets > compute-secrets.env
copy      :  scp compute-secrets.env NODE:/tmp/
node      :  sudo install -o root -g root -m 0600 /tmp/compute-secrets.env \
                 /etc/hagistack/secrets.env
             shred -u /tmp/compute-secrets.env
```

`compute-secrets` emits exactly five values —
`RABBIT_PASS NOVA_SERVICE_PASS PLACEMENT_SERVICE_PASS NEUTRON_SERVICE_PASS
METADATA_PROXY_SECRET` — and **refuses to write to a terminal**, because a
terminal keeps scrollback. The suite proves the boundary rather than trusting
it: `S5b` builds a controller-shaped secrets file with recognisable values and
fails if any database password, `MYSQL_ROOT_PASS` or `ADMIN_PASSWORD` — name or
value — appears in the output. `S5c` checks all five wanted ones do.

`phase_compute_secrets` then refuses to continue if the file is absent (with the
three commands above in the error), if it is not mode 0600, or if any of the
five keys is missing — naming the missing ones.

### 3.3 Refusing early, before anything is installed

`nova-compute` pulls libvirt and qemu — hundreds of megabytes. So the
controller's reachability is checked in **preflight**, before any install:
TCP connect to `5000` (identity), `9292` (image), `8778` (placement), `5672`
(message queue) and `6642` (OVN southbound). Any of them closed is a hard error
naming which, with the `ss -ltn` command to run on the controller.

`S4a` asserts the refusal; `S4b` and `S4e` assert that **nothing was installed**
by a refused run.

`--controller-ip` is validated as an address that can belong to another machine:
`0.x`, `127.x`, `169.254.x`, multicast, `255.255.255.255` and anything that is
not a plain IPv4 unicast address are refused, as is a value equal to this node's
own management address ("run `all-in-one` on the controller itself"). Twelve
cases in `S1n`–`S1u`, including an injection attempt, and `S1v` checks that no
rejected value executed anything.

### 3.4 Closing the loop

A compute node cannot confirm its own registration — no database, no admin
credential, by design. So `compute-add` ends by telling you to run, **on the
controller**:

```
sudo hagistack discover-hosts
```

which runs `nova-manage cell_v2 discover_hosts --by-service` and prints the
compute service list and the hypervisor list on either side of it.

What `compute-add` *can* check locally, and does: that its chassis appears in
the controller's southbound database, by asking that database directly
(`ovn-sbctl --db=tcp:$CONTROLLER_IP:6642`) for a chassis whose name matches this
host's `system-id`.

---

## 4. A pre-existing bug the suite found

Not part of the plan. `S2e` was written to check the new configuration keys can
be read from a config file, and it failed for keys that had nothing to do with
step 6.

```
error: /tmp/ok.env line 2: unknown key 'CONTROLLER_IP'.
     Allowed keys: ... PROVIDER_BRIDGE CONTROLLER_IP IMAGE_NAME ...
```

The key it called unknown was right there in the list it printed. The allowlist
test was:

```sh
case " $CONFIG_KEYS " in *" $key "*) ;;
```

`CONFIG_KEYS` is written over several lines, so a key that happens to sit at the
**end of a line** is followed by a newline, not a space, and never matched.

This was **already shipped**: in step 5's `CONFIG_KEYS`, the line-final keys were
`FLOATING_START` and `REGION_NAME`. Both were refused from `hagistack.env` —
while working perfectly on the command line, which is how it survived five steps.
`FLOATING_START` is a **required** setting, so the documented "put it in
hagistack.env" workflow was broken for it.

Fixed by normalising the list once (`CONFIG_KEYS_FLAT`) and searching that.
`S2e` now walks **every** key in `CONFIG_KEYS` and fails if any is rejected from
a file, so the shape of the bug cannot come back.

---

## 5. What was run, and what it settles

Ubuntu 26.04.1 LTS amd64 container (`ubuntu:26.04`), no systemd, ~1 GB free.

```
tests/container-step6.sh   PASS 68   FAIL 0   UNVERIFIED 7   guest exit 0
```

Covered: `bash -n`; ShellCheck `-S warning` clean on the shell and on both
suites; the implemented-vs-verified separation in `status` and `--help`; absence
of the stale STEP 1 header; twelve image-input validations and eight
controller-IP validations, none of which executed anything; every `CONFIG_KEYS`
entry accepted from a config file; `IMAGE_URL=$(...)` refused rather than run;
the pinned digest checked **against the publisher's live `SHA256SUMS`**;
`compute-add` refusing an unreachable controller, a missing secrets file, a
world-readable one and an incomplete one, with nothing installed in any case;
`compute-secrets` leaking no database or admin credential; and a source audit —
no `openstack delete`, no `DROP`, no `rm -rf` against a system path, no write to
the dashboard conffile, no `[database]` on a compute node, no gateway chassis.

### 5.1 Recorded UNVERIFIED — not forced into a PASS

| | Why a container cannot settle it |
|---|---|
| Horizon serving, and logging in | needs apache + a live Keystone |
| guest boot | needs libvirt and a real hypervisor |
| the initial resources actually being created | needs a live control plane |
| a second node's OVN chassis | needs two machines |
| node-to-node Geneve | needs two machines |
| `compute-add` → Placement registration | needs a live controller |
| unit startup and ordering | needs systemd |

All seven are GCE acceptance items.

### 5.3 Regression, and four stale assertions this change exposed

All four suites, same container, after the change:

| Suite | Result | Guest exit | Baseline |
|---|---|---|---|
| `container-step6.sh` | **PASS 69 / FAIL 0 / UNVERIFIED 7** | 0 | new |
| `container-step5.sh` | **PASS 68 / FAIL 0 / UNVERIFIED 7** | 0 | 68/0/7 — unchanged |
| `container-audit.sh` | **PASS 39 / FAIL 0 / UNVERIFIED 1** | 0 | 39/0/1 — unchanged |
| `container-verify.sh` | **PASS 63 / FAIL 0 / UNVERIFIED 8** | 0 | 63/0/8 — unchanged |

Getting there took two rounds, and both are worth recording because neither was
a defect in the shell.

**Round 1: seven step-5 failures that were a full disk.** The first step-5
regression run came back 44/7/22, including `all-in-one` exiting **100** instead
of 4. Exit 100 is `apt-get`'s, and the captured log says why:

```
Setting up python3-os-ken (4.1.1-1ubuntu2) ...
[Errno 28] No space left on devicedpkg: unrecoverable fatal error, aborting:
E: Sub-process /usr/bin/dpkg returned an error code (2)
error: aborted at hagistack:1839 (exit 100)
```

The guest had ~700 MB free and the step-5 suite installs the whole stack. That
is a resource constraint, not a configuration defect, and the two are not
allowed to be confused here: freeing the guest to 2 GB and re-running gave
68/0/7 with `S2a-exit4` through `S2f` all passing. No code was changed to make
that happen.

**Round 2: four assertions pinned to wording this change deliberately removed.**
These *were* fixed, in the harness, because the behaviour they were guarding is
still wanted and only the wording moved:

| Assertion | Was | Now |
|---|---|---|
| `container-step5` `S4a` helper extraction | lifted `write_service_auth()` by name | also lifts `write_service_auth_at()`. `write_service_auth` became a thin wrapper, so the extracted copy called a function that was not there and **every adapter block silently came out empty** — which is what `S4i`/`S4j`/`S4k` were reporting |
| `container-verify` `B6` | `compute-add` must exit **3** saying "not implemented yet" | `compute-add` must exit **1** naming `--controller-ip`. A subcommand that is no longer a stub must not keep passing a stub test |
| `container-verify` `B7`, `G3`; `container-audit` `4.2`, `4.7` | matched `STEP <n> COMPLETE/INCOMPLETE` and `phases pending` | match the word `INCOMPLETE` and `not implemented`, with the step number optional. The step number was exactly the thing that kept going stale |
| `container-audit` `4.3` | `STEP <n> COMPLETE` | `\bCOMPLETE\b` |

That last one bit on the way past: widening it to `COMPLETE( |$)` made it match
**inside `INCOMPLETE`**, so the assertion fired on the very banner it exists to
accept. The word boundary is load-bearing.

### 5.2 About the step 4 Keystone connection-pool failure

Step 4 hit `QueuePool limit of size 5 overflow 50 reached` at 98% disk with the
database idle at 56 of 1024 connections, and the note at the time leaned on the
disk figure. **Disk pressure is a correlation, not a diagnosis.** A SQLAlchemy
pool exhausts when connections are checked out and not returned; at least these
are consistent with what was seen and none was ruled out:

* `apache2` running more WSGI processes/threads than the pool allows, so each
  process holds its own pool and the *server* limit is irrelevant;
* requests blocking on a token cache that was not answering, holding their
  database connection for the duration;
* the eventlet→native-threading migration in 2026.1 changing effective
  concurrency defaults;
* genuine connection leaks under a container's constrained I/O.

The honest position is that it was **not diagnosed**, and the one number that
was measured — 56 of 1024 server-side connections — says the *server* was not
the limit. It is a GCE item; on a real host, `[database] max_pool_size` /
`max_overflow` and the vhost's `processes`/`threads` should be read together
before anything is blamed.

---

## 6. Files changed

| File | |
|---|---|
| `hagistack` | header rewritten; `0.5.0-step5` → `0.6.0-step6`; `_preflight_host` split out; five new settings with validation; `CONFIG_KEYS_FLAT` bug fix; `write_service_auth_at`; `phase_horizon`; `phase_bootstrap_resources`; six `compute_*` phases; `compute-secrets` and `discover-hosts`; banners, `status` and `--help` rewritten around implemented-vs-verified |
| `hagistack.env.example` | image settings and `CONTROLLER_IP` |
| `tests/container-step6.sh` | new, 68 assertions |
| `README.md` | rewritten status section, Horizon / initial-resources / `compute-add` sections, and the verification section |
| `tests/container-step5.sh` | extraction now lifts `write_service_auth_at` |
| `tests/container-audit.sh` | three assertions re-pinned off the step number |
| `tests/container-verify.sh` | `compute-add` is no longer expected to be a stub |
| `../rocky10.2/README.md`, `../rocky10.2/probe-repos.sh` | the Rocky re-investigation and a re-runnable probe |
| `STEP6_HORIZON_RESOURCES_EVIDENCE.md` | this file |
