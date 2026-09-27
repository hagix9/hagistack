# Step 2 — Keystone: packaging evidence and verification

- Date: 2026-09-27
- Subject: `ubuntu26.04/hagistack` version `0.2.0-step2`
- Scope: Keystone identity only. **No Glance, Placement, Neutron/OVN, Nova, Horizon or compute-add.**
- Environment: `ubuntu:26.04` → **Ubuntu 26.04.1 LTS amd64**, nerdctl/containerd in an already-running
  lima VM. **No systemd in the container.** `/src` mounted read-only.
  No GCE, AWS or Sinter operation; no macOS host service or network change.

## 1. How Keystone actually starts on Ubuntu 26.04 — measured, not assumed

Everything below came from installing the real package in a clean Ubuntu 26.04 container.

| Question | Command | Result |
|---|---|---|
| Version | `dpkg-query -W keystone` | **`2:29.0.0-0ubuntu1.2`** (= OpenStack 2026.1 Gazpacho); `keystone-manage --version` → `29.0.0` |
| uwsgi or Apache? | package Depends; `dpkg -l \| grep uwsgi` | **Apache**. Depends on `apache2` and `libapache2-mod-wsgi-py3` (`5.0.2-1build2`). **No uwsgi package is installed or referenced.** |
| Is there a Keystone systemd unit? | `dpkg -L keystone`; `ls /usr/lib/systemd/system \| grep -i keystone` | **None.** `dpkg -L keystone` lists exactly one file. Keystone is served by **`apache2.service`** |
| What does the package ship? | `dpkg -L keystone` | `/etc/apache2/sites-available/keystone.conf` — and nothing else |
| Bind and port | the shipped vhost | `Listen 5000` + `<VirtualHost *:5000>` → **port 5000, all interfaces**. No admin port (the historical 35357 is gone) |
| WSGI entry point | the vhost | `WSGIScriptAlias / /usr/bin/keystone-wsgi-public`, `WSGIDaemonProcess … user=keystone group=keystone` |
| Enabled by default? | `ls /etc/apache2/sites-enabled/` | **Yes** — `keystone.conf` symlink present immediately after install |
| Who owns keystone.conf? | `dpkg -S /etc/keystone/keystone.conf` | **`keystone-common`** (not `keystone`, not `python3-keystone`), mode **0640 keystone:keystone** |
| Shipped DB setting | `grep ^connection` | `sqlite:////var/lib/keystone/keystone.db` — **must be replaced** |
| Key repositories | keystone's own option defaults | `[fernet_tokens] key_repository=/etc/keystone/fernet-keys/` (created by the package, 0700 keystone:keystone); `[credential] key_repository=/etc/keystone/credential-keys/` (**not created by the package**) |
| Token/credential providers | option defaults | both already `fernet`; set explicitly only to pin them |
| Password in argv? | `keystone-manage bootstrap --help`, `cli.py` | reads **`OS_BOOTSTRAP_PASSWORD`** and the other `OS_BOOTSTRAP_*` variables → the password never has to appear in argv |
| Are the key setups idempotent? | ran `fernet_setup`/`credential_setup` twice, compared digests | **stable — YES** |

The shipped vhost, verbatim:

```apache
Listen 5000

<VirtualHost *:5000>
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    LimitRequestBody 114688
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined
    …
</VirtualHost>
```

**Decision and why.** hagistack drives **`apache2.service`** and the package's own vhost. It does not
invent a unit name, does not install uwsgi, and does not write its own vhost — the packaged one
already listens on 5000 and points at the right WSGI entry point. The only Apache change hagistack
makes is a `ServerName` conf (so Apache stops warning it cannot determine the FQDN) and
`a2ensite keystone`, which is a no-op when the package has already enabled it.

## 2. What the Keystone phase does

1. Install `keystone` (pulls `apache2` + `libapache2-mod-wsgi-py3`) and `python3-openstackclient`.
2. Refuse to continue unless MariaDB is reachable **and** the `keystone` database exists.
3. Probe that the `keystone` DB user can reach MariaDB **over TCP on 127.0.0.1** — Keystone uses
   `mysql+pymysql`, which cannot use a unix socket. The probe's password goes in a `0600` defaults
   file: not argv, not the environment.
4. Set `[database] connection`, `[token] provider`, `[credential] provider` with the idempotent
   `ini_set`; keep the file `0640 keystone:keystone`.
5. `keystone-manage db_sync` as the **keystone** user (`runuser`), reporting created / already-current
   / migrated by counting tables before and after.
6. `fernet_setup` and `credential_setup` **only when the key repository is empty**, so a re-run can
   never rotate keys and invalidate live tokens.
7. `keystone-manage bootstrap` with the password passed through `OS_BOOTSTRAP_PASSWORD`.
8. Write `/etc/hagistack/admin-openrc` at `0600`, rewritten only when the content would change.
9. `ServerName`, `a2ensite`, then start or reload `apache2` under systemd.
10. Verify the endpoint answers and that **an admin can actually authenticate**. The phase is marked
    done **only** if that succeeds; otherwise it reports SKIPPED and the run exits 4.

## 3. Defects this verification found and fixed

| # | Defect | Why it mattered | Fix |
|---|---|---|---|
| 1 | The connection string pointed at `${MGMT_IP}` | `phase_database` pins MariaDB to `bind-address = 127.0.0.1`, so this is **refused on any real all-in-one host** — not just in the container | use `127.0.0.1`; it is the same host and keeps the credential off the wire |
| 2 | A `db_sync` failure printed an empty error | `keystone-manage` logs to its own file and writes nothing to stderr, so the first failure reported nothing actionable | probe TCP reachability first with a precise message; on failure also tail `/var/log/keystone/keystone.log`, with the password substituted out and `password`/`secret` lines filtered |
| 3 | The TCP precheck aborted with `die` | Every other unreachable-dependency path uses `note_skip` + exit 4 | `note_skip`, consistent with database/rabbitmq/memcached |
| 4 | ShellCheck SC2034 — `KEYSTONE_VHOST_AVAIL` assigned but unused | — | removed |
| 5 | `ini_set`/`ini_get` read the file with a bare `awk` | `keystone.conf` is `0640 keystone:keystone`, so this fails when the shell runs unprivileged under sudo | read through `$SUDO cat` |

### And three test-harness faults, two of which produced false confidence

- **Vacuous stability checks.** `K5b`/`K5c`/`K5e` compared `sha256sum` of files that did not exist —
  missing == missing, so they reported "NOT rotated" about artefacts that were never created. `K5j`
  compared two empty strings. A `digest_of` helper now returns the literal `ABSENT` and a `stable`
  helper **fails** when either side is absent. Added `K5l`/`K5m`: the bootstrapped admin must keep the
  same row id and the same stored credential hash across re-runs.
- **A socket-only database.** The suite started MariaDB with `--skip-networking`, which disables TCP
  entirely, so `mysql+pymysql` could never connect. Controlled experiment on one server:

  ```
  --skip-networking        TCP:3306 listening = 0   db_sync -> 0 tables
  --bind-address=127.0.0.1 TCP:3306 listening = 1   db_sync -> 49 tables
  ```

  The suite now starts MariaDB the way a real host does and asserts the listener exists (`K3a2`).
- **`shellcheck` was not installed** in the Step 2 container, so `K0b` could not run.

Without the first of these I would have reported a passing Step 2 built on a Keystone that had never
created a single table.

## 4. Results

### Step 2 suite — 51 PASS / 0 FAIL / 2 UNVERIFIED

Start methods (no systemd in the container, so both were started by hand and recorded):

```
MariaDB : mariadbd-safe --bind-address=127.0.0.1 (manual, no systemd)
Apache  : apachectl -k start (manual, no systemd)
```

| ID | Status | Detail |
|---|---|---|
| `K0a-bash-n` | PASS | parses |
| `K0b-shellcheck` | PASS | no warnings (-S warning) |
| `K0c-version` | PASS | hagistack 0.2.0-step2 |
| `K0d-region-flag` | PASS | --region-name documented |
| `K0e-help-honest` | PASS | help states it is not a working OpenStack |
| `K0f-status-keystone` | PASS | status mentions keystone |
| `K0g-status-honest` | PASS | status states what is missing |
| `K1a-region-default` | PASS | RegionOne [default] |
| `K1b-region-env` | PASS | EnvRegion [environment] |
| `K1c-region-cli` | PASS | CliRegion [command line] |
| `K1d-region-invalid` | PASS | bad region refused (rc=1) |
| `K1e-region-no-exec` | PASS | command substitution in REGION_NAME not executed |
| `K2a-exit4` | PASS | exit 4 with no DB |
| `K2b-skip-reported` | PASS | keystone skip reported |
| `K2c-no-marker` | PASS | no keystone state marker |
| `K2d-no-false-complete` | PASS | did not claim COMPLETE |
| `K3a-mariadb-start` | PASS | started via: mariadbd-safe --bind-address=127.0.0.1 (manual, no systemd) (11.8.6-MariaDB-5ubuntu0.1 from Ubuntu) |
| `K3a2-mariadb-tcp` | PASS | MariaDB is listening on TCP 3306 (what pymysql needs) |
| `K3b-conf-written` | PASS | keystone.conf updated |
| `K3c-conn-mysql` | PASS | connection points at MariaDB |
| `K3d-no-sqlite` | PASS | sqlite default replaced |
| `K3e-conf-perms` | PASS | keystone.conf 640 keystone:keystone |
| `K3f-db-sync` | PASS | 49 tables in the keystone schema |
| `K3g-fernet` | PASS | fernet keys present (0 1 ) |
| `K3h-credkeys` | PASS | credential keys present |
| `K3i-key-owner` | PASS | fernet key owned by keystone |
| `K3j-bootstrap-user` | PASS | admin user present in the identity DB |
| `K3k-bootstrap-endpoints` | PASS | 3 identity endpoints in the catalogue |
| `K3l-openrc-perms` | PASS | admin-openrc mode 600 |
| `K4a-no-secret-in-log` | PASS | no secret value appears in the run output |
| `K4b-conn-has-pass` | PASS | DB password present in keystone.conf (0640, expected) |
| `K4c-no-pass-in-argv` | PASS | admin password not visible in process args |
| `K4d-no-bootstrap-echo` | PASS | bootstrap password never echoed |
| `K5a-data-survives` | PASS | sentinel row intact after re-run |
| `K5b-fernet-stable` | PASS | fernet keys unchanged |
| `K5c-credkeys-stable` | PASS | credential keys unchanged |
| `K5d-secrets-stable` | PASS | secrets.env unchanged |
| `K5e-openrc-stable` | PASS | admin-openrc unchanged |
| `K5f-conf-stable` | PASS | keystone.conf unchanged |
| `K5g-conf-reported` | PASS | re-run reports conf unchanged |
| `K5h-fernet-reported` | PASS | re-run reports keys untouched |
| `K5i-schema-reported` | PASS | re-run reports schema current |
| `K5j-no-dup-users` | PASS | user count stable at 1 across the re-run |
| `K5l-admin-id-stable` | PASS | bootstrapped admin keeps the same id across the re-run |
| `K5m-admin-cred-stable` | PASS | stored admin credential unchanged by the re-run |
| `K5k-third-run` | PASS | data intact after a 3rd run |
| `K6a-apache-skip-honest` | PASS | no systemd -> keystone reported SKIPPED: The schema, fernet keys, credential keys and bootstrap ARE i |
| `K6b-no-marker-unserved` | PASS | keystone NOT marked done while unserved |
| `K6c-endpoint-manual` | PASS | identity endpoint answers (started via: apachectl -k start (manual, no systemd)) |
| `K6d-admin-auth` | PASS | admin authenticated; token issued (value not shown) |
| `K6e-catalogue` | PASS | 3 keystone endpoints in the catalogue |
| `K6f-systemd-startup` | UNVERIFIED | apache2.service startup + unit ordering: GCE acceptance (B0a/B0b) |
| `K6g-openstack-accept` | UNVERIFIED | real OpenStack acceptance (Glance..Horizon): not in step 2 |

### Step 1 regression (same build)

| Suite | Result |
|---|---|
| `container-audit.sh` | **40 PASS / 0 FAIL / 0 UNVERIFIED** |
| `container-verify.sh` | **65 PASS / 0 FAIL / 6 UNVERIFIED** |
| `container-dbtest.sh` | **28 PASS / 0 FAIL / 3 UNVERIFIED** (the 3 are RabbitMQ, which will not start in a container) |

The first regression run showed 5 failures. All five were **stale literal expectations**, not
behaviour regressions — the suites hard-coded `STEP 1`, `0.1.0-step1` and `base layer:`. Verified
directly: `--version` reports `0.2.0-step2`, the help still discloses incompleteness (the sentence
simply wraps across two lines, which the old single-line grep missed), and `status` reports
`implemented layer: INCOMPLETE`. The suites now assert the property — `STEP [0-9]+ INCOMPLETE`,
`^hagistack [0-9]+\.[0-9]+\.[0-9]+-step[0-9]+`, `(base|implemented) layer:` — so this class of false
failure will not recur at Step 3.

## 5. Re-run behaviour, measured

```
run 1:  49 tables created, fernet keys 0/1, credential keys 0/1,
        admin user + 3 identity endpoints, admin-openrc 0600
run 2:  "keystone.conf already correct (unchanged)"
        "fernet token keys already present — not touched"
        "identity schema already current (49 tables, unchanged)"
        fernet digest, credential digest, secrets.env, admin-openrc, keystone.conf  ALL unchanged
        user count stable at 1; admin row id unchanged; stored credential hash unchanged
run 3:  planted sentinel row still present
```

## 6. Still not verified

| Item | Why | Goes to |
|---|---|---|
| `apache2.service` startup and systemd unit ordering | no systemd in a container; Apache was started by hand | GCE 区分 B — B0a / B0b |
| MariaDB/RabbitMQ under systemd | same | GCE 区分 B — B0b |
| Glance, Placement, Neutron/OVN, Nova, Horizon; any instance or network | **not implemented in step 2** | later steps, then GCE |
| Provider network, Floating IP, physical LAN | not implemented | GCE 区分 B / C |

Nothing here has run on real Ubuntu 26.04 hardware or on a GCE VM. **`all-in-one` at this stage
produces base services plus identity only — it is not a usable OpenStack**, and the banner, `--help`
and `status` all say so.
