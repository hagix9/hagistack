# Step 5 — Nova on Ubuntu 26.04: what was measured, and what it proves

Base: branch `docs/openstack-renewal-research`, on top of `c993011` (step 4).

Nova is where the previous steps' assumptions could easily have been carried
over by analogy — three different startup models already exist in this
deployment, and Nova uses a fourth combination. Everything below was measured
by unpacking the actual `.deb` files, **without installing them** (the guest
had 1.6 GB free and `nova-compute` pulls libvirt and qemu).

---

## 1. Packaging facts (measured, not inferred from the other services)

All packages at **`3:33.0.0-0ubuntu3.1`** (OpenStack 2026.1) except where noted.

| Package | What it actually ships |
|---|---|
| `nova-api` | `/etc/apache2/sites-available/nova-api.conf` with its own **`Listen 8774`**, `WSGIScriptAlias / /usr/bin/nova-api-wsgi`, `processes=5 threads=1 user=nova`. postinst runs `apache2_invoke ensite`. **No systemd unit.** |
| `nova-api-metadata` | a *separate* vhost, **`Listen 8775`**, `/usr/bin/nova-metadata-wsgi` |
| `nova-conductor` | `nova-conductor.service` — `Type=simple`, `User=nova`, `ExecStart=/etc/init.d/nova-conductor systemd-start` |
| `nova-scheduler` | `nova-scheduler.service` — same shape |
| `nova-compute` | `nova-compute.service` — same shape, and `After=libvirtd.service … neutron-ovs-cleanup.service` |
| `nova-common` | `/etc/nova/nova.conf`, `api-paste.ini`, `rootwrap.conf` (postinst sets `/etc/nova/*` to `0640 root:nova`) |
| `nova-compute-kvm` | `/etc/nova/nova-compute.conf` containing `compute_driver=libvirt.LibvirtDriver` and `[libvirt] virt_type=kvm` |
| `nova-api-os-compute` | **empty transitional package** — not used |

Four findings that would have been wrong if guessed:

1. **No postinst touches the database.** Not one of the packages runs `db sync`
   or anything `cell_v2`. All schema and cell work is hagistack's job.
2. **`/etc/nova/nova.conf`: the archive and the installed file differ, and the
   first version of this document got it wrong.** `dpkg-deb -c` shows the
   archive storing it `0644 root:root`, and I wrote that hagistack therefore had
   to tighten it or local users could read the credentials. The step 5 suite
   contradicted that (`S3e`), and a follow-up measurement settled it: the
   `nova-common` postinst runs

   ```
   find /etc/nova -exec chown root:nova "{}" +
   find /etc/nova -type f -exec chmod 0640 "{}" +
   ```

   so what actually lands on disk is **`0640 root:nova`**. hagistack's
   `chown root:nova` / `chmod 0640` is therefore *enforcement* of the packaged
   state — worth keeping, because the file is rewritten on every run and the
   mode must not drift — not a fix for a packaging gap. The lesson is the one
   this project keeps relearning: an archive listing is not the installed
   state.
3. **`/etc/init.d/nova-compute` passes `--config-file=/etc/nova/nova-compute.conf`**
   in addition to the default `nova.conf`. So the virtualisation type belongs in
   `nova-compute.conf`, which is also where the package already put it.
4. **`[api] auth_strategy` does not exist in Nova 33** — it is not in
   `nova/conf/api.py`. It is a familiar line from older guides, and it is not
   written here. Likewise `[glance] api_servers` is *deprecated since 21.0.0*
   ("Support for image service configuration via standard keystoneauth1 Adapter
   options was added in 17.0.0"), so Glance is reached through the catalogue
   with `[glance] valid_interfaces` instead.

`[neutron] metadata_proxy_shared_secret` is **absent from the shipped sample**
(oslo hides secret options) but **is** defined in `nova/conf/neutron.py`. The
code was read to confirm the group and name rather than copying a tutorial.

### 1.1 `nova-manage`, from the shipped code

```
CATEGORIES = { api_db, cell_v2, db, placement, libvirt,
               volume_attachment, image_property, limits }
db      : sync, version, archive_deleted_rows, purge, online_data_migrations, ...
api_db  : sync, version
cell_v2 : simple_cell_setup, map_cell0, map_instances, map_cell_and_hosts,
          verify_instance, discover_hosts, create_cell, list_cells,
          delete_cell, update_cell, list_hosts, delete_host
```

`map_cell0` is idempotent by construction: it catches `DBDuplicateEntry` and
prints "Cell0 is already setup", returning 0.

### 1.2 Why no password ever reaches a command line

`_map_cell0()` with no `--database_connection` derives the cell0 URL itself:

```python
connection = CONF.database.connection
url = sqla_url.make_url(connection)
url = url.set(database=url.database + '_cell0')
```

So the cell0 database must be named `<nova database>_cell0` — i.e. `nova_cell0`
— and hagistack provisions exactly that name in `phase_database`, then calls
`nova-manage cell_v2 map_cell0` **with no arguments**. The password stays in
`nova.conf` (mode 0640) and never appears in `ps`. `create_cell` is likewise
called without `--database_connection`/`--transport-url`.

`cell_v2 list_cells` prints the database and transport URLs *including
passwords*, so the phase matches its output for a cell name but never logs it.

---

## 2. What the phase does

**`phase_nova`** (control plane): installs `nova-api nova-api-metadata
nova-conductor nova-scheduler`; gates on MariaDB, the `nova`, `nova_api` and
`nova_cell0` databases, Keystone and memcached; writes `nova.conf`
(`my_ip`, `transport_url`, both database URLs, `keystone_authtoken`,
`service_user`, `placement`, `neutron`, `glance valid_interfaces`,
`service_metadata_proxy` + the shared secret, `vnc`, `lock_path`); tightens the
file to `0640 root:nova`; runs `api_db sync` → `cell_v2 map_cell0` → `db sync`;
creates `cell1` **only if it is not already mapped**; registers the `compute`
service and three `:8774/v2.1` endpoints; enables both vhosts and reloads
Apache; starts conductor and scheduler; and marks the phase done **only after**
`openstack compute service list` succeeds.

**`phase_nova_compute`** (hypervisor): checks `phase_done nova` **before
installing anything** — `nova-compute` pulls libvirt and qemu, and there is no
point putting hundreds of megabytes on a host whose control plane is not up.
Then it writes `compute_driver` and `[libvirt] virt_type` (plus `cpu_mode=none`
under emulation) into `nova-compute.conf`, starts `libvirtd` and `nova-compute`,
waits for the compute service to register, runs
`cell_v2 discover_hosts --by-service`, and marks the phase done only after the
hypervisor is visible to the API.

Placement and Neutron are **runtime** dependencies, not configuration ones: if
their phases have not completed, the run warns ("nova cannot schedule until it
does", "instances will have no network") and carries on, rather than refusing to
configure. The completion marker still depends on the compute API actually
answering.

### 2.1 Virtualisation type

`/dev/kvm` is probed in preflight (already present since step 1) and resolves
`VIRT_TYPE` to `kvm` or `qemu`; `--virt-type` overrides it through the normal
precedence chain. Under `qemu` the run warns that guests are 10–50× slower and
sets `[libvirt] cpu_mode = none`, which is the only model that works reliably
without hardware virtualisation. **A container cannot boot a guest at all**, and
nothing in this step treats a running service as evidence that one can.

---

## 3. Container verification — deliberately light

The step 4 run showed this container cannot keep Keystone, Apache and memcached
alive together (Keystone's client-side SQLAlchemy pool exhausted while the
database server sat idle). Repeating that here would prove nothing about a real
host and would cost the whole guest disk, so the step 5 suite was scoped before
it was written:

**In scope:** `bash -n`, ShellCheck, the new input validation, honest skipping,
the packaging assertions above, configuration generation and its idempotence,
the three compute databases, and secret handling.

**Out of scope, on purpose:** bringing the control plane up again. The compute
API, the cells commands actually running, the hypervisor, and guest boot are
UNVERIFIED and go to the GCE acceptance.

### 3.1 Configuration generation, tested against the real file

`ini_set`, `ini_get`, `write_authtoken` and `write_service_auth` are lifted out
of the shell with `sed` (the same technique the step 1 audit suite uses for
`gen_secret`) and applied to the **packaged** `/etc/nova/nova.conf`. That tests
the code that ships rather than a copy of it, and it needs no services at all.
The suite then checks each key in its own section, that both `sqlite` defaults
are gone, that a second application changes not one byte, and that a *changed*
value is rewritten in place rather than appended. A separate assertion
(`S4t`) greps `phase_nova` for every one of those `ini_set` calls, so the helper
test cannot drift away from what the phase actually asks for.

### 3.2 Secret handling

Besides the usual checks (no secret in any log or artefact, `secrets.env` 0600,
`NOVA_SERVICE_PASS` generated), step 5 adds two static guarantees that matter
because `nova-manage` *can* take credentials on its command line:

* `S6e` fails if `nova-manage` is ever called with `--database_connection` or
  `--transport-url`.
* `S6f` fails if a `cell_v2 list_cells` result could be echoed, because that
  output contains the database and transport passwords.

---

## 4. UNVERIFIED — sent to the GCE acceptance, not called passed

| Item | Why not here | Where |
|---|---|---|
| authenticated compute API on :8774, `openstack compute service list` | needs a live Keystone/Apache; this container could not sustain one | GCE node1 |
| `api_db sync`, `db sync`, `map_cell0`, `create_cell` actually executing | same — they run after the Keystone gate | GCE node1 |
| `nova-compute`, `libvirtd`, hypervisor registration, `discover_hosts` | `nova-compute` pulls libvirt and qemu; no systemd and no `/dev/kvm` here | GCE node1 |
| **booting a guest VM** | not attempted; a container cannot prove it | GCE node1 |
| startup and ordering of `nova-conductor`, `nova-scheduler`, `nova-compute` under systemd | no systemd in a container | GCE B0a/B0b |
| `compute-add`, Geneve between two nodes | needs the second node | GCE node1+node2 |
| the step 4 Neutron API items | **they stay UNVERIFIED.** This step does not revisit or reinterpret them | GCE node1 |

## 5. The Keystone pool exhaustion is carried forward as an observation

Step 4 recorded `QueuePool limit of size 5 overflow 50 reached` with the MariaDB
server idle at 56 of 1024 connections and the container filesystem at 98%. That
remains **an observed fact whose cause is not settled**: low disk is one
plausible contributor, but so are the number of WSGI processes, the guest's I/O
latency under qemu, and Keystone's own pool defaults. Step 5 does not adopt any
single explanation, does not tune around it, and re-checks it on GCE where the
disk, the CPU and systemd are all different. Nova adds two more WSGI
applications (`:8774` and `:8775`) to the same Apache, which makes the GCE
measurement more interesting, not less.

---

## 6. Result table

Ubuntu 26.04.1 container, no systemd, MariaDB started by hand
(`mariadbd-safe --bind-address=127.0.0.1 --max-connections=1024`):

```
PASS=68   FAIL=0   UNVERIFIED=7      guest exit 0
```

| Block | Result |
|---|---|
| `S0` static and surface (8) | `bash -n`, ShellCheck clean on the shell and on both new suites, version, `status` naming the compute layer and saying guest boot is not verified, help honesty, repo-wide scan that every "usable/finished OpenStack" mention is a negation |
| `S1` input validation (7) | `--virt-type xen`, `kvm;touch /tmp/S1` and a missing value all refused with nothing executed; `kvm`/`qemu` accepted; environment tier honoured; `/dev/kvm` absent → `virt_type=qemu` |
| `S2` honest skipping (6) | both nova phases skip, exit 4, no state marker, no `COMPLETE`, and `nova.conf` still carries the package default |
| `S3` packaging (9) | vhosts on 8774/8775, no `nova-api` unit, conductor/scheduler units `User=nova`, installed `nova.conf` `0640 root:nova` and the phase re-applying it, `[api] auth_strategy` genuinely absent, `metadata_proxy_shared_secret` genuinely defined, `cell_v2` offered |
| `S4` configuration generation (21) | every key in its own section, both sqlite defaults replaced, second application byte-identical, a changed value rewritten once rather than appended, and `phase_nova` proven to ask for each key |
| `S5` compute databases (7) | `nova`, `nova_api`, `nova_cell0` created; one credential logs into all three; grants on `nova_cell0`; planted row and `secrets.env` intact across a re-run; re-run reports existing databases left untouched |
| `S6` secrets (6) | `NOVA_SERVICE_PASS` generated, `secrets.env` 0600, nothing leaked to logs or argv, `nova-manage` never handed a DSN, cell listings never printed |
| `S7` (7) | the UNVERIFIED items in §4 |

Two defects were found by this suite and fixed before the clean run:
ShellCheck `SC2178` in `phase_nova_compute` (a local `seen` shadowing the
config parser's `seen` array — renamed `reg_hosts`), and an unused variable left
in the step 4 suite by the step 4 retry refactor. The first run was
`PASS=64 FAIL=2 UNVERIFIED=8`, guest exit 1, with both FAILs being those
ShellCheck findings; the S3e correction in §1 came from the same run.
