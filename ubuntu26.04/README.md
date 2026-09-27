# hagistack — Ubuntu Server 26.04 LTS

A plain-Bash OpenStack deployment shell. Not OpenStack-Ansible, not
Kolla-Ansible, not Packstack, not DevStack.

## Current status: Step 2 — **this is not a working OpenStack yet**

| | |
|---|---|
| Version | `0.2.0-step2` |
| Target OS | Ubuntu Server **26.04 LTS** only (`amd64`; `arm64` accepted but untested) |
| Target OpenStack | 2026.1 Gazpacho, from the Ubuntu 26.04 archive |

**Implemented**

- `all-in-one` skeleton, argument parsing, `--help`, `status`
- preflight: OS gate, architecture → qemu package, KVM/QEMU detection,
  memory and disk checks, full validation of the required settings,
  single-NIC warning
- secret generation into `/etc/hagistack/secrets.env` (mode `0600`)
- base packages, **MariaDB**, **RabbitMQ**, **memcached**
- **Keystone identity**: schema, fernet and credential keys, `bootstrap`,
  Apache/mod_wsgi on port 5000, and an `admin-openrc` you can authenticate with

**Not implemented yet**

Glance, Placement, Neutron/OVN, Nova, Horizon, initial resources
(flavor / image / network / router / security group / keypair), and the whole
of `compute-add`. `compute-add` exits with a clear "not implemented" message
and status 3.

So: after `all-in-one` finishes you have a database, a message queue, a cache
and a working identity service. **There is no image store, no scheduler, no
network and no compute — you cannot create a network or boot an instance.**
The command prints a banner saying exactly that, and `hagistack status` lists
which phases are implemented versus pending.

### Keystone

Served by **`apache2.service`** with `libapache2-mod-wsgi-py3`. There is no
Keystone systemd unit on Ubuntu — the `keystone` package ships exactly one
file, `/etc/apache2/sites-available/keystone.conf`, which carries its own
`Listen 5000` and points at `/usr/bin/keystone-wsgi-public`, and installing it
enables the site. hagistack drives that packaged vhost rather than inventing a
unit or installing uwsgi. The evidence behind each of those statements is in
`STEP2_KEYSTONE_EVIDENCE.md`.

```sh
. /etc/hagistack/admin-openrc
openstack token issue
```

Re-running never rotates the fernet or credential keys, never rewrites the
admin credential, and never drops the schema.

### Completion is not assumed

A base service that cannot be reached is not quietly skipped. The run reports
`STEP 1 INCOMPLETE`, names the phases it skipped, writes **no** state marker for
them, and **exits 4**. `hagistack status` says `base layer: INCOMPLETE` and lists
what is missing. Only a run in which every implemented phase actually did its
work prints `STEP 1 COMPLETE (BASE LAYER)` and exits 0.

This is the normal outcome in a container with no systemd, and it is not a
failure of the shell — but it is not a completed step 1 either.

| Exit | Meaning |
|---|---|
| 0 | success |
| 1 | configuration or preflight error |
| 2 | usage error |
| 3 | subcommand not implemented yet |
| 4 | ran to the end, the layer is incomplete (a service was unreachable) |

## Usage

```sh
cp hagistack.env.example hagistack.env   # edit it
sudo ./hagistack all-in-one              # or: --check for preflight only
./hagistack status
```

Required settings: `EXT_NIC`, `PROVIDER_CIDR`, `PROVIDER_GATEWAY`,
`FLOATING_START`, `FLOATING_END`. Everything else is autodetected or defaulted
(including `REGION_NAME`, which defaults to `RegionOne`).

### Configuration

Precedence is **command line > environment > `./hagistack.env` > default**, and
it applies to *every* option, including `--tenant-cidr`, `--dns-server` and
`--virt-type`. `--check` prints the resolved value and its source for each key:

```
==> resolved configuration
    EXT_NIC            eth0                   [command line]
    TENANT_CIDR        10.1.1.0/24            [environment]
    DNS_SERVER         172.24.4.1             [default]
```

Giving a key an empty value on any tier is an error rather than a silent
fall-through, so "explicitly blank" is never mistaken for "not supplied".
Repeating a flag is allowed; the last occurrence wins.

**The config file is parsed, never executed.** Only blank lines, `#` comments
and `KEY=VALUE` are accepted; `KEY` must be a known setting and `VALUE` may
contain only letters, digits and `. _ - : / @ + =`. Unknown keys, duplicate
keys, malformed lines and values containing shell metacharacters are refused,
and a rejected value is never echoed back in the error. Use
`--env-file /dev/null` to ignore all config files.

## Safety properties

These are the failures of the 2013-era shells in this repository, and the
rules that replace them:

| Old behaviour | Now |
|---|---|
| `MYSQL_PASS=nova`, `ADMIN_PASSWORD=secrete` committed to Git | No password in the source. Generated per host into `/etc/hagistack/secrets.env` (`0600`), git-ignored, and **reused unchanged** on re-runs |
| an unconditional database drop on every run | **No `DROP DATABASE` anywhere.** An existing database is detected and left untouched. There is no flag to bypass this |
| `cat … \| tee -a /etc/sysctl.conf` duplicating on every run | `ini_set` edits key-by-key and rewrites the file only when the content actually changes |
| `rm -rf /var/log/nova/*` | Nothing is deleted |
| No `set -e`; ran to completion after failures | `set -Eeuo pipefail` plus an `ERR` trap that reports the failing line. `-E` matters: without it the trap is not inherited by functions, so it never fires |
| Config file `source`d, making every value executable | The file is **parsed**. `KEY=$(command)` and backquoted values are refused, not run |
| — | A service that cannot be reached does not count as done: no state marker, `STEP 1 INCOMPLETE`, exit 4 |
| AppArmor disabled, libvirt opened on TCP with `auth_tcp="none"`, MariaDB bound to `0.0.0.0` | None of these. MariaDB is pinned to `127.0.0.1`, memcached to the management IP |

Re-running `all-in-one` is safe and is part of the acceptance criteria.

## What has actually been verified

Verified in an **Ubuntu 26.04.1 LTS amd64 container** (no systemd): `bash -n`,
ShellCheck, `--help`, subcommand resolution, the `compute-add`
not-implemented path, input validation, config-generation idempotence,
secret file permissions and value stability across runs, refusal of
code-execution payloads in the config file, the full precedence matrix, and the
incomplete-run reporting and exit code.

With **MariaDB started by hand** inside the container (`mariadbd-safe
--skip-networking`, recorded as such): database and user creation, login as the
`nova` user to both the `nova` and `nova_api` databases with one credential, and
survival of a planted row across three consecutive runs.

Keystone specifically was verified in that container with MariaDB and Apache
started **by hand** (`mariadbd-safe --bind-address=127.0.0.1`,
`apachectl -k start` — both recorded as such): 49-table schema, fernet and
credential keys, bootstrap, and `openstack token issue` succeeding as admin,
with every artefact unchanged across three consecutive runs.

**Not verified anywhere yet**: service startup *under systemd*, unit ordering
and dependency resolution, **RabbitMQ** (it would not start in the container,
even by hand), and every OpenStack service beyond Keystone. Those are GCE
acceptance items — see `../HAGISTACK_VERIFICATION_SCOPE_2026-09-26.md` §5.

Nothing in this shell has been run on real Ubuntu 26.04 hardware or on a
GCE VM.
