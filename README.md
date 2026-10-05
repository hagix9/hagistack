# Hagistack

English | [日本語](README.ja.md)

Hagistack installs **OpenStack 2026.1 (Gazpacho)** on **Ubuntu Server 26.04 LTS** or
**Rocky Linux 10.2** with one plain-Bash script per distribution.

## What is Hagistack?

- **A plain-Bash OpenStack installer.** There is no configuration-management
  engine, no templates and no container runtime. It is Bash, `apt`/`dnf`,
  `systemctl`, and the OpenStack command-line tools.
- **One distribution, one installer script.** Each supported platform has a single
  `hagistack` script. The script runs a fixed sequence of phases:
  1. database
  2. message queue
  3. Keystone
  4. Glance
  5. Placement
  6. OVN
  7. Neutron
  8. Nova
  9. Horizon
  10. initial resources
- **Written to be read before it is run.** The comments explain why each step is
  there. An operator can follow the phases in order and see what will change on
  the machine.
- **Deliberately small.** Hagistack is not OpenStack-Ansible, Kolla-Ansible,
  Packstack or DevStack. Those projects solve other problems, such as
  multi-node orchestration, containerised services and development
  environments. Hagistack aims at one thing: a short, directly readable path to
  a working all-in-one node, plus extra compute nodes.

## Supported platforms

| | Ubuntu Server 26.04 LTS | Rocky Linux 10.2 |
|---|---|---|
| Architecture | amd64 (verified). arm64 is accepted by preflight but has **not been verified** | x86_64 only (other architectures are refused) |
| OpenStack | 2026.1 Gazpacho | 2026.1 Gazpacho |
| Package source | The Ubuntu 26.04 archive | RPMs **you build first** with `build-rpms.sh`, from pinned 2026.1 release tarballs |
| Verified | Two nodes on Google Compute Engine, 2026-09-28 | Two nodes on Google Compute Engine, 2026-09-29 |

Other OS versions are refused by preflight. One exception: the Rocky script
continues with a warning on other EL10 distributions (RHEL, AlmaLinux,
CentOS 10), which have not been verified.

## Choose your platform

- **[Ubuntu Server 26.04 LTS →](ubuntu26.04/README.md)**
  Packages come from the Ubuntu archive. There is nothing to build first.
- **[Rocky Linux 10.2 →](rocky10.2/README.md)**
  Nobody publishes OpenStack 2026.1 for EL10. **You must build the OpenStack RPM
  repository before you can install.**

## Quick start

1. **Choose your platform** and open its guide (links above).
2. **Prepare the host.** You need:
   - a fresh machine running the supported OS;
   - root access through `sudo`;
   - an existing interface to name as the provider NIC;
   - the provider network values: CIDR, gateway and floating-IP range.

   On Rocky, you also need a built RPM repository.
3. **Run preflight only:**
   `sudo ./hagistack all-in-one --check …`
   It validates every setting and prints the resolved configuration. It changes
   nothing.
4. **Install:** `sudo ./hagistack all-in-one …`

   To add a compute node:
   1. Run `compute-secrets` on the controller.
   2. Run `compute-add` on the new node.
   3. Run `discover-hosts` back on the controller.
5. **Check:** run `sudo ./hagistack status`. Then boot a test guest, as shown in
   your platform guide.

The exact commands and options are in the platform guides.

## What gets installed

On the all-in-one (controller + compute) node:

| Component | Details |
|---|---|
| Keystone | Identity API on port 5000, served by the web server through mod_wsgi |
| Glance | Image API on port 9292 |
| Placement | Placement API on port 8778 |
| Nova | Compute API (8774) and metadata API (8775); conductor, scheduler and compute (libvirt with KVM, or QEMU when `/dev/kvm` is not usable); cells v2 with `cell0` and `cell1` |
| Neutron | Networking API on port 9696 with the ML2/OVN driver, and the OVN metadata agent |
| Open vSwitch / OVN | OVN northbound and southbound databases and `ovn-northd` on the controller; `ovn-controller` on every node; Geneve tunnels between nodes |
| Horizon | Dashboard on port 80: `/horizon` on Ubuntu, `/dashboard` on Rocky |
| MariaDB | Bound to `127.0.0.1` only |
| RabbitMQ | One `openstack` user |
| memcached | Bound to the management IP |

It also creates a small set of initial resources:

- the `m1.tiny` flavor;
- a digest-verified CirrOS 0.6.3 image;
- the `hagistack-provider` network (flat, external) and the `hagistack-tenant`
  network (Geneve);
- `hagistack-router`;
- ICMP and SSH rules on the admin project's `default` security group;
- the `hagistack-key` keypair.

A compute node added with `compute-add` gets `nova-compute`, libvirt,
Open vSwitch, `ovn-controller` and the OVN metadata agent.

**Not included:**
- Cinder (block storage), Swift, and any other OpenStack service not listed above;
- the noVNC console proxy.

## Commands

The subcommands and options are the same on both platforms except where the
table says otherwise.

| Command | Where | What it does |
|---|---|---|
| `all-in-one [options]` | controller | Installs the controller and compute services on this host |
| `all-in-one --check [options]` | controller | Preflight only: validates the settings and prints the resolved configuration. Changes nothing |
| `compute-add --controller-ip IP [options]` | new node | Turns this host into an additional compute node |
| `compute-secrets` | controller | Writes the five credentials a compute node needs to standard output. It refuses to write to a terminal |
| `discover-hosts` | controller | Maps newly registered compute hosts into the Nova cell |
| `status` | any node | Shows the version, phase markers and service state |
| `--help`, `--version` | — | Usage text; version string |

- **Rocky only:** `all-in-one` and `compute-add` also need `--repo-url`, which
  points at the RPM repository you built.
- **Exit status:**
  - `0`: success.
  - `1`: a configuration or preflight error.
  - `2`: a usage error.
  - `4`: the run reached the end, but at least one phase was skipped, so the
    deployment is **incomplete**.
  - Any other non-zero status means a command failed and the run stopped.

## Verification status

**Verified** on Google Compute Engine. The virtual machines had nested
virtualisation, so `virt_type=kvm`. One all-in-one node and one added compute
node were used on each platform:

| | Ubuntu 26.04 (2026-09-28) | Rocky 10.2 (2026-09-29) |
|---|---|---|
| `all-in-one` completes with no skipped phase | ✓ | ✓ |
| Authenticated calls to Keystone, Glance, Placement, Neutron and Nova | ✓ | ✓ |
| `compute-add` on a second node; both hypervisors registered and mapped into the cell | ✓ | ✓ |
| Guest reaches ACTIVE on both nodes | ✓ | ✓ |
| cloud-init completes in a guest (metadata service, SSH key injected) | ✓ | ✓ |
| Two guests on different nodes ping each other; the traffic was captured on the Geneve tunnel | ✓ | ✓ |
| A second run changes nothing: exit 0, no unit restarted | ✓ | ✓ |
| Horizon admin sign-in: an authenticated session, not only a 200 on the login page | ✓ (first run of the day, before the final fix) | ✓ |

**Implemented but not verified:**
- the arm64 path on Ubuntu;
- other EL10 distributions with the Rocky script;
- hosts with an active host firewall;
- deployments of more than two nodes.

**Out of scope or not included:** see *Known limitations*.

## Known limitations

**Not included:**
- **Provider NIC attachment.** Hagistack **never attaches the provider NIC to the
  provider bridge** (`br-ex`). It checks that the NIC you name exists, but it
  leaves the bridge without a physical port. Until you attach a NIC yourself,
  provider networks and floating IPs do not reach any physical LAN.
- **Services beyond the list above.** Cinder (volumes), Swift and other services
  are not installed.
- **noVNC.** The console proxy is not installed, so the Horizon console tab does
  not work.
- **Firewall.** No host firewall rules are configured.

**Not verified:**
- a physical-LAN provider path, and reaching floating IPs from outside the host;
- live migration;
- three or more nodes;
- arm64 on Ubuntu;
- SELinux in enforcing mode on Rocky. Rocky was verified only with SELinux
  **permissive**, and the installer switches the host to permissive (see the
  Rocky guide);
- RPM `%check` test suites. The Rocky RPMs were built with `--nocheck`.

**Not supported:**
- operating system versions or OpenStack releases other than those listed above;
- Rocky on a non-x86_64 host.

## Safety properties

These properties come from the code and its tests:

- **No fixed passwords.** Every credential is generated on the first run. It is
  written to `/etc/hagistack/secrets.env` with mode `0600`, then reused
  unchanged on later runs, so a re-run never rotates a live password.
- **The config file is parsed, never executed.** Only `KEY=VALUE` lines for known
  keys are accepted, and a value may contain only letters, digits and
  `. _ - : / @ + =`.
- **No database is ever dropped.** Databases and users are created only if they
  are absent.
- **Compute nodes get the minimum.** `compute-secrets` hands over exactly five
  credentials. A compute node never receives a database password or the admin
  password.
- **Designed to be re-run.**
  - Configuration is edited key by key.
  - Initial resources are show-or-create by name.
  - A second run on the verified hosts exited 0 and restarted nothing.
  - A failed run is **not** rolled back: fix the cause and run the same command
    again.
- **An incomplete run says so.** If a phase is skipped because a service it
  depends on is unreachable, the run exits with status `4`, not `0`.
- **Keep the nodes on a trusted management network.** The APIs, RabbitMQ, the
  OVN southbound database and memcached listen on the management network, and
  Hagistack adds no firewall rules.

## Repository layout

```text
README.md, README.ja.md     this page
LICENSE                     MIT License for Hagistack's own code (see License below)
ubuntu26.04/                Ubuntu Server 26.04 installer, tests and verification records
acceptance/                 dated acceptance and investigation records
rocky10.2/                  Rocky Linux 10.2 installer, RPM build tooling and spec adaptation rules
rocky10.2/third-party/      third-party files with their own licence (Neutron patches, Apache-2.0)
```

## History

- **2012:** Hagistack started as "centstack", a set of shell scripts for
  installing OpenStack on CentOS 6, and was soon renamed Hagistack.
- **2012–2013:** it followed OpenStack from Essex to Havana on CentOS 6 and
  Ubuntu 12.04–13.10.
- **2014:** an Ansible-based version was split off into a separate repository.
- **2026:** Hagistack was rewritten from scratch as a plain-Bash installer for
  OpenStack 2026.1.

The 2012–2013 scripts were removed from the tree in 2026. They are still in the
Git history.

## License

Hagistack's own code and documentation in the current tree are licensed under the
[MIT License](LICENSE). Copyright (c) 2026 Shiro Hagihara.

Third-party material keeps its own licence:

- `rocky10.2/third-party/neutron/` holds two OpenStack Neutron patches under the
  Apache License 2.0. They are **not** covered by the MIT License. The licence text,
  the upstream attribution and the source commits are in the same directory
  (`LICENSE`, `NOTICE.md`).
- Quotations from other projects in the records, such as upstream OpenStack commit
  messages in `acceptance/` or configuration excerpts in `ubuntu26.04/`, remain under
  their original licences.
- The software these scripts install or build (OpenStack, RDO packaging, Python
  packages and so on) is not part of this repository. It is fetched when you run
  them and keeps its own licences.

The MIT License applies to the files in the current tree. It is not a statement
about the terms of earlier revisions in the Git history.
