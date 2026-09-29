# Hagistack for Ubuntu Server 26.04 LTS

English | [日本語](README.ja.md)

[← Hagistack overview](../README.md)

## Overview

`hagistack` is a single Bash script. It installs OpenStack 2026.1 (Gazpacho) from
the Ubuntu 26.04 archive. It has two modes:

- **`all-in-one`** puts the whole control plane and a compute service on one host.
- **`compute-add`** adds further compute nodes to that host.

What gets installed:

- **Services:** Keystone, Glance, Placement, Nova (cells v2), and Neutron with
  ML2/OVN.
- **Infrastructure:** Open vSwitch and OVN, MariaDB, RabbitMQ and memcached.
- **Dashboard:** Horizon.
- **Initial resources:** a small set a first guest can use (see
  [What all-in-one creates](#what-all-in-one-creates)).

## Requirements

**Host**

- **Operating system:** Ubuntu Server 26.04 LTS. Preflight refuses any other
  OS or version.
- **Architecture:**
  - `amd64` is verified.
  - `arm64` is accepted, and the matching QEMU package and CirrOS image are
    selected, but this path has **not been verified**.
- **Privileges:** root through `sudo`.
- **Init system:** systemd.
- **Memory:** 8 GiB or more for all-in-one. Preflight warns below 8 GiB.
- **Disk:** 40 GiB or more free on `/` is recommended. Preflight warns below
  20 GiB.
- **Virtualisation:** a usable `/dev/kvm` gives `virt_type=kvm`. Without it,
  Hagistack falls back to `qemu` software emulation. That emulation is 10–50×
  slower and suitable only for a boot test.
- **Internet access:**
  - the Ubuntu archive, for packages;
  - `download.cirros-cloud.net`, for the first guest image. You can use a local
    file instead: see `--image-file`.

**Network**

- **Management IP.** This is the address the services and the other nodes use.
  By default it is the source address of the route to `1.1.1.1`. Override it
  with `--mgmt-ip`.
- **A provider NIC (`--ext-nic`).**
  - It must exist on the host.
  - Hagistack **does not attach it to the provider bridge** (see
    [Known limitations](#known-limitations)).
  - On a single-NIC host you may name the management NIC. Preflight warns, and
    Hagistack still never moves the management address.
- **Provider network values:**
  - a CIDR;
  - a gateway inside that CIDR;
  - a floating-IP range inside that CIDR, with the gateway outside the range.

**For a second node**

- Ubuntu Server 26.04 LTS.
- A hostname different from the controller's.
- The ability to reach the controller's management IP on these TCP ports:
  - 5000 (Keystone)
  - 9292 (Glance)
  - 8778 (Placement)
  - 5672 (RabbitMQ)
  - 6642 (OVN southbound)

  `compute-add` checks all five before it installs anything.
- Geneve tunnels between the nodes use **UDP 6081**. This port is not checked.
- Hagistack configures no host firewall. If you run one, you must open these
  ports yourself. A host with an active firewall has not been verified.

## Files

| File | Purpose |
|---|---|
| `hagistack` | The installer |
| `hagistack.env.example` | A commented example configuration file. Copy it to `hagistack.env` |
| `tests/` | Container-based regression suites for static checks, input validation, configuration generation and re-run safety, plus their fixture |
| `STEP*_*.md`, `GCE_ACCEPTANCE_2026-09-28*.md` | Dated development and verification records. They describe the state **at the time they were written**, not the current state |

## Configuration

Each setting can come from four tiers. **Precedence:**
command line > environment > config file > default.

- **Config file.** Hagistack uses the file named by `--env-file`. Without that
  option, it takes the first of these that exists:
  1. `./hagistack.env`
  2. `hagistack.env` next to the script
  3. `/etc/hagistack/hagistack.env`
- **Ignore all config files:** pass `--env-file /dev/null`.
- **Environment through `sudo`.** `sudo` normally drops environment variables,
  so pass them explicitly:
  `sudo env TENANT_CIDR=10.20.0.0/24 ./hagistack all-in-one …`
- **Empty values.** An empty value on any tier is an error. It is not treated as
  "not given".

| Option | Key | Required | Default |
|---|---|---|---|
| `--ext-nic NAME` | `EXT_NIC` | all-in-one | — |
| `--provider-cidr CIDR` | `PROVIDER_CIDR` | all-in-one | — |
| `--provider-gateway IP` | `PROVIDER_GATEWAY` | all-in-one | — |
| `--floating-start IP` | `FLOATING_START` | all-in-one | — |
| `--floating-end IP` | `FLOATING_END` | all-in-one | — |
| `--tenant-cidr CIDR` | `TENANT_CIDR` | | `10.10.10.0/24` |
| `--dns-server IP` | `DNS_SERVER` | | the provider gateway |
| `--provider-physnet NAME` | `PROVIDER_PHYSNET` | | `physnet1` |
| `--provider-bridge NAME` | `PROVIDER_BRIDGE` | | `br-ex` |
| `--image-name NAME` | `IMAGE_NAME` | | `cirros-0.6.3-x86_64` (amd64) |
| `--image-url URL` | `IMAGE_URL` | | the CirrOS 0.6.3 download URL |
| `--image-sha256 HEX` | `IMAGE_SHA256` | set it whenever you change the URL | the published CirrOS digest. A download that does not match is refused |
| `--image-file PATH` | `IMAGE_FILE` | | — (use a local file instead of downloading) |
| `--controller-ip IP` | `CONTROLLER_IP` | compute-add | — |
| `--mgmt-ip IP` | `MGMT_IP` | | autodetected |
| `--virt-type kvm\|qemu` | `VIRT_TYPE` | | autodetected from `/dev/kvm` |
| `--region-name NAME` | `REGION_NAME` | | `RegionOne` |

**The config file is parsed, never executed.** It may contain only:

- blank lines;
- `#` comments;
- `KEY=VALUE` lines for the keys above.

Values may contain only letters, digits and `. _ - : / @ + =`. Hagistack refuses
unknown keys, duplicate keys and shell metacharacters. **Do not put passwords
in it.** Hagistack generates its own (see
[Sensitive and generated files](#sensitive-and-generated-files)).

A minimal `hagistack.env` for all-in-one (the values are placeholders):

```sh
EXT_NIC=eth1
PROVIDER_CIDR=192.0.2.0/24
PROVIDER_GATEWAY=192.0.2.1
FLOATING_START=192.0.2.100
FLOATING_END=192.0.2.200
```

## Preflight check

```sh
git clone https://github.com/hagix9/hagistack.git
cd hagistack/ubuntu26.04
cp hagistack.env.example hagistack.env      # then edit it
sudo ./hagistack all-in-one --check
```

`--check` runs preflight only and **changes nothing**. It checks the following:

- the OS version and architecture;
- whether KVM or QEMU will be used;
- memory and disk;
- that the provider NIC exists;
- that every address and CIDR is valid and consistent (the gateway and the
  floating range inside the CIDR, the gateway outside the range);
- the management IP;
- the image source. A download URL is refused unless it comes with a SHA-256
  digest.

It then prints every resolved setting together with where the value came from:
command line, environment, file or default.

- Exit status `0`: preflight passed.
- Exit status `1`: a setting is wrong. The message names the setting.

## All-in-one installation

```sh
sudo ./hagistack all-in-one
```

The phases run in this order:

1. preflight
2. secrets
3. base packages
4. MariaDB
5. RabbitMQ
6. memcached
7. Keystone
8. Glance
9. Placement
10. OVS/OVN
11. Neutron
12. Nova
13. nova-compute
14. Horizon
15. initial resources

On a GCE `n2-standard-4` a clean run took about 25 minutes. The closing banner
shows the following:

- the dashboard URL;
- where the admin credentials are;
- a command to boot a test guest;
- the exact commands for adding a compute node, including this controller's
  management IP.

### What all-in-one creates

Each resource is show-or-create by name. None is deleted or recreated.

| Resource | Details |
|---|---|
| Flavor | `m1.tiny`: 1 vCPU, 512 MiB RAM, 1 GiB disk |
| Image | `cirros-0.6.3-x86_64` (amd64). The file is verified against the SHA-256 digest **before** it is uploaded |
| External network | `hagistack-provider`: flat, external, on `physnet1`. Its subnet holds the floating range and has no DHCP |
| Tenant network | `hagistack-tenant` (Geneve) |
| Router | `hagistack-router`: gateway on the provider network, plus an interface on the tenant subnet |
| Security group rules | ICMP and TCP/22 on the admin project's `default` group |
| Keypair | `hagistack-key` (RSA 3072). The private key is `/etc/hagistack/hagistack-key`, mode `0600` |

## Add a compute node

Run each step on the machine shown.

**1. On the controller:** write the credentials a compute node needs to a file.
The command refuses to write to a terminal.

```sh
(umask 077; sudo ./hagistack compute-secrets > compute-secrets.env)
```

Your shell, not `hagistack`, creates `compute-secrets.env`, so its mode comes
from your umask. The `umask 077` above makes it readable by you only.

The file holds exactly these five credentials:

- `RABBIT_PASS`
- `NOVA_SERVICE_PASS`
- `PLACEMENT_SERVICE_PASS`
- `NEUTRON_SERVICE_PASS`
- `METADATA_PROXY_SECRET`

It holds no database password and no admin password.

**2. Copy the file to the new node over a secure channel.** Then delete the
controller's copy.

```sh
scp compute-secrets.env NODE:/tmp/
shred -u compute-secrets.env
```

**3. On the new node:** install the credentials, then run `compute-add` with the
controller's management IP.

```sh
sudo install -d -m 0750 /etc/hagistack
sudo install -o root -g root -m 0600 /tmp/compute-secrets.env /etc/hagistack/secrets.env
shred -u /tmp/compute-secrets.env
cd hagistack/ubuntu26.04
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP
```

`compute-add` never generates secrets. It stops if
`/etc/hagistack/secrets.env` is missing. Before it installs anything, it checks
the following:

- `--controller-ip` is a usable unicast address, and it is not this node's own
  address;
- the controller answers on TCP 5000, 9292, 8778, 5672 and 6642.

The node is deliberately given much less than the controller:

- no database access (it reaches the cell database only through
  `nova-conductor`);
- no admin credential;
- no provider bridge mapping.

**4. Back on the controller:** map the new host into the cell.

```sh
sudo ./hagistack discover-hosts
```

## Verify the deployment

On any node:

```sh
sudo ./hagistack status
```

`status` shows the following:

- the phase markers on this host;
- whether the all-in-one is complete, or which phases are missing;
- the state of every service unit.

On a compute node, it tells you to run `discover-hosts` on the controller,
because the node itself cannot see the cell database.

On the controller, as root:

```sh
sudo -i
. /etc/hagistack/admin-openrc
openstack compute service list
openstack hypervisor list
openstack network agent list
openstack server create --flavor m1.tiny --image cirros-0.6.3-x86_64 \
    --network hagistack-tenant --key-name hagistack-key demo1
openstack server show demo1 -c status
openstack console log show demo1        # cloud-init output
```

What to expect:

- the guest reaches `ACTIVE`, in about 12–18 seconds on the verified hosts;
- the console log shows cloud-init fetching its metadata.

Guests on `hagistack-tenant` can reach each other across nodes over Geneve,
which is verified. They **cannot** reach a physical LAN until you attach a NIC
to the provider bridge.

## Horizon

- **URL:** `http://MGMT_IP/horizon/`
- **Web server:** Apache on port 80, the same server that runs the API vhosts.
- **User:** `admin`. The password is `OS_PASSWORD` in `/etc/hagistack/admin-openrc`.
  Hagistack never prints it.
- **Settings:** Hagistack writes them to a snippet that the packaged settings
  load. The package's own `local_settings.py` is never edited.
- **Checks during the run:** the Horizon phase confirms that the effective
  Keystone URL and cache location are the ones it wrote, and that the login page
  answers.
- **`ALLOWED_HOSTS`:** left as the package ships it (`['*']`).
- **Console tab:** does not work. The noVNC proxy is not installed.

**Verification.** A real admin sign-in was verified on GCE on 2026-09-28: the
POST returned 302, a session cookie was issued, and protected pages rendered
for `admin`. That check ran in the first acceptance run of the day. The second
run, which produced the current code, did not repeat the sign-in check.

## Re-running Hagistack

`all-in-one` and `compute-add` are designed to be run again. A second run on the
verified hosts exited 0, reported every step as already done, and restarted no
service.

On a re-run:

- **Secrets:** existing secrets are reused, never rotated.
- **Databases:** never dropped. Existing databases are left untouched.
- **Configuration:** files are edited key by key, and only when a value
  changes. A service is restarted only when its configuration is newer than
  its running process.
- **Initial resources:** show-or-create by name. They are never deleted or
  recreated.
- **Base packages:** skipped once they are installed. Set `HAGISTACK_REDO=1` to
  reinstall them.

Hagistack does **not** roll back. If a run fails, it prints the line where it
stopped. Fix the cause and run the same command again.

A re-run is **not a reconfiguration tool**. If you change addresses or names
after the first run, the resources and endpoints that already exist are left in
place. Hagistack warns about endpoints that differ, but it does not rewrite
them.

## Command reference

```text
sudo ./hagistack all-in-one      [options]    controller + compute on this host
sudo ./hagistack all-in-one --check [options] preflight only; changes nothing
sudo ./hagistack compute-add --controller-ip IP [options]
sudo ./hagistack compute-secrets > FILE       controller; refuses a terminal
sudo ./hagistack discover-hosts               controller; map new compute hosts
sudo ./hagistack status                       phase markers and service state
./hagistack --help | --version
```

Options for both modes:

- `--mgmt-ip`
- `--virt-type`
- `--region-name`
- `--env-file`
- `--check`

The options for `all-in-one` and `compute-add` are listed under
[Configuration](#configuration).

| Exit status | Meaning |
|---|---|
| 0 | Success |
| 1 | Configuration or preflight error, or a check that stopped the run |
| 2 | Usage error: unknown command or option |
| other non-zero | A command failed. Hagistack prints `aborted at hagistack:LINE` and stops |
| 4 | The run reached the end, but a phase was skipped because a service it needs was unreachable. The deployment is **incomplete**. Fix the cause and re-run |

## Sensitive and generated files

| Path | Contents | Mode |
|---|---|---|
| `/etc/hagistack/secrets.env` | Every generated credential. On a compute node, only the five delivered keys | `0600` |
| `/etc/hagistack/admin-openrc` | Admin credentials for the `openstack` CLI | `0600` |
| `/etc/hagistack/hagistack-key` | Private key of the `hagistack-key` keypair | `0600` |
| `/var/lib/hagistack/state/*.done` | Phase markers, used by `status` and on re-runs | — |
| `/var/lib/openstack-dashboard/secret_key` | Horizon's Django secret key | `0600` |
| `./hagistack.env` | Your settings. It must not contain passwords | — |
| `/etc/systemd/system/apache2.service.d/10-hagistack-procsubset.conf` | Apache drop-in (see [Troubleshooting](#troubleshooting)) | `0644` |

Never commit `secrets.env`, `admin-openrc` or `hagistack.env`. The repository's
`.gitignore` excludes them.

## Troubleshooting

- **Exit status 4 or "INCOMPLETE".** A service Hagistack depends on did not
  answer, so a phase was skipped. The output names the phase and the check to
  run. Fix it and re-run.
- **The closing banner says "NOTHING HERE IS VERIFIED ON REAL HARDWARE".** The
  headline predates the GCE verification. The line below it and
  [Verified environment](#verified-environment) give the current status.
- **A guest goes to ERROR with `VirtualInterfaceCreateException`.** Check the
  Apache drop-in:

  ```sh
  systemctl show apache2 -p ProcSubset      # must be "all"
  ```

  Ubuntu 26.04's `apache2.service` sets `ProcSubset=pid`. That setting hides
  `/proc/meminfo` from the Neutron API workers, and every OVN port event is then
  dropped. Hagistack writes a drop-in that sets `ProcSubset=all`, and it checks
  that the workers can read `/proc/meminfo`.
- **`compute-add` stops: "the controller is not reachable on: …".** Nothing was
  installed. On the controller, check that the listed ports are listening:

  ```sh
  ss -ltn | grep -E '5000|9292|8778|5672|6642'
  ```

  Then check that no firewall blocks this node. The OVN southbound database
  listens on the controller's management IP, so `--controller-ip` must be that
  address.
- **Guests are slow or time out.** Check `virt_type` in the preflight output.
  `qemu` means that `/dev/kvm` is not usable.

## Verified environment

Two virtual machines on Google Compute Engine, 2026-09-28:

- **Image:** `ubuntu-2604-resolute-amd64`.
- **Virtualisation:** nested virtualisation enabled, `virt_type=kvm`.
- **node1:** `all-in-one` on an n2-standard-4 with 60 GB of disk.
- **node2:** `compute-add` on an n2-standard-2 with 40 GB of disk.

Verified:

- every phase completed;
- authenticated calls to Keystone, Glance, Placement, Neutron and Nova;
- cells v2 with both hosts mapped;
- a Placement resource provider for each node;
- two OVN chassis;
- a guest ACTIVE on each node, in 18 s and 12 s;
- cloud-init completed;
- two guests on different nodes pinged each other, and the packets were captured
  on the Geneve tunnel;
- Horizon admin sign-in (see [Horizon](#horizon));
- second runs of `all-in-one` and `compute-add` exited 0 and restarted nothing.

The details are in `GCE_ACCEPTANCE_2026-09-28.md` and
`GCE_ACCEPTANCE_2026-09-28_RUN2.md`.

## Known limitations

**Not included**

- **Provider NIC attachment.** The provider NIC is **never attached** to
  `br-ex`, and `br-ex` gets no address. Provider networks and floating IPs
  reach no physical LAN until you attach a NIC yourself. On a single-NIC host,
  attaching the management NIC would move the management address and can cut
  off SSH.
- **Other services.** Cinder (volumes), Swift and other OpenStack services are
  not installed.
- **noVNC.** The console proxy is not installed.
- **Firewall.** No host firewall is configured. The APIs, RabbitMQ, the OVN
  southbound database and memcached listen on the management network, so keep
  the nodes on a trusted network.

**Not verified**

- a physical-LAN path, or reaching floating IPs from outside the host;
- live migration;
- three or more nodes;
- `arm64`;
- hosts with an active host firewall.
