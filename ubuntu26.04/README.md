# hagistack — Ubuntu Server 26.04 LTS

A plain-Bash OpenStack deployment shell. Not OpenStack-Ansible, not
Kolla-Ansible, not Packstack, not DevStack.

## Current status: Step 1 — **this is not a working OpenStack yet**

| | |
|---|---|
| Version | `0.1.0-step1` |
| Target OS | Ubuntu Server **26.04 LTS** only (`amd64`; `arm64` accepted but untested) |
| Target OpenStack | 2026.1 Gazpacho, from the Ubuntu 26.04 archive |

**Implemented**

- `all-in-one` skeleton, argument parsing, `--help`, `status`
- preflight: OS gate, architecture → qemu package, KVM/QEMU detection,
  memory and disk checks, full validation of the required settings,
  single-NIC warning
- secret generation into `/etc/hagistack/secrets.env` (mode `0600`)
- base packages, **MariaDB**, **RabbitMQ**, **memcached**

**Not implemented yet**

Keystone, Glance, Placement, Neutron/OVN, Nova, Horizon, initial resources
(flavor / image / network / router / security group / keypair), and the whole
of `compute-add`. `compute-add` exits with a clear "not implemented" message
and status 3.

So: after `all-in-one` finishes you have a database, a message queue and a
cache. **You cannot create a network or boot an instance.** The command prints
a banner saying exactly that, and `hagistack status` lists which phases are
implemented versus pending.

## Usage

```sh
cp hagistack.env.example hagistack.env   # edit it
sudo ./hagistack all-in-one              # or: --check for preflight only
./hagistack status
```

Required settings: `EXT_NIC`, `PROVIDER_CIDR`, `PROVIDER_GATEWAY`,
`FLOATING_START`, `FLOATING_END`. Everything else is autodetected or
defaulted. Precedence: command line > environment > `./hagistack.env` >
defaults.

## Safety properties

These are the failures of the 2013-era shells in this repository, and the
rules that replace them:

| Old behaviour | Now |
|---|---|
| `MYSQL_PASS=nova`, `ADMIN_PASSWORD=secrete` committed to Git | No password in the source. Generated per host into `/etc/hagistack/secrets.env` (`0600`), git-ignored, and **reused unchanged** on re-runs |
| an unconditional database drop on every run | **No `DROP DATABASE` anywhere.** An existing database is detected and left untouched. There is no flag to bypass this |
| `cat … \| tee -a /etc/sysctl.conf` duplicating on every run | `ini_set` edits key-by-key and rewrites the file only when the content actually changes |
| `rm -rf /var/log/nova/*` | Nothing is deleted |
| No `set -e`; ran to completion after failures | `set -euo pipefail` plus an `ERR` trap that reports the failing line |
| AppArmor disabled, libvirt opened on TCP with `auth_tcp="none"`, MariaDB bound to `0.0.0.0` | None of these. MariaDB is pinned to `127.0.0.1`, memcached to the management IP |

Re-running `all-in-one` is safe and is part of the acceptance criteria.

## What has actually been verified

Verified in an **Ubuntu 26.04 container** (no systemd): `bash -n`,
ShellCheck, `--help`, subcommand resolution, the `compute-add`
not-implemented path, input validation, config-generation idempotence,
secret file permissions and value stability across runs.

**Not verified anywhere yet**: service startup under systemd, unit ordering,
MariaDB/RabbitMQ operation, and every OpenStack service. Those are GCE
acceptance items — see `../HAGISTACK_VERIFICATION_SCOPE_2026-09-26.md` §5.

Nothing in this shell has been run on real Ubuntu 26.04 hardware or on a
GCE VM.
