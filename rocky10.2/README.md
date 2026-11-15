# Hagistack for Rocky Linux 10.2

English | [日本語](README.ja.md)

[← Hagistack overview](../README.md)

> **Where the OpenStack RPMs come from.**
> Rocky Linux does not ship OpenStack, and nobody publishes OpenStack 2026.1 for
> EL10. `hagistack` therefore gets the 2026.1 RPMs itself, in one of four ways
> chosen with `--rpm-source` (see [RPM sources](#rpm-sources)):
> download a published, pinned release (`github`, the default), **build them
> from source on this host** (`build`), reuse a controller's set (`bundle`), or
> use a repository you already run (`--repo-url`). You do not need to build RPMs
> or create a DNF repository by hand.
>
> **Status, 2026-11-09:** no RPM release has been published yet, so the
> default `github` source stops with an explanation. Use `--rpm-source build`
> (or `--repo-url`) until a release is published.

## Overview

`hagistack` is a single Bash script. It installs OpenStack 2026.1 (Gazpacho) on
Rocky Linux 10.2 from RPMs built from the released 2026.1 tarballs. It supports
four configurations:

- **`all-in-one`** puts the whole control plane and a compute service on one host.
- **`controller`** installs the control plane only, with no hypervisor.
- **`compute-add --local`** later adds the hypervisor to that controller, which
  makes it equivalent to an all-in-one host. Nothing on the controller is
  reconfigured.
- **`compute-add --controller-ip IP`**, run on another host, adds a remote
  compute node. Repeat it for each additional node.

What gets installed:

- **Services:** Keystone, Glance, Placement, Nova (cells v2), and Neutron with
  ML2/OVN.
- **Infrastructure:** Open vSwitch and OVN, MariaDB, RabbitMQ and memcached.
- **Dashboard:** Horizon.
- **Initial resources:** a small set a first guest can use.

## Requirements

**Host**

- **Operating system:** Rocky Linux 10.2.
  - Other EL10 distributions (RHEL, AlmaLinux, CentOS 10) continue with a
    warning and have **not been verified**.
  - Anything else is refused.
- **Architecture:** x86_64 only. Other architectures are refused.
- **Privileges:** root through `sudo`.
- **Init system:** systemd.
- **Memory:** 8 GB or more for all-in-one. Preflight warns below about 7 GB.
- **Disk:** 20 GB or more free on `/`. The verified all-in-one node had 60 GB.
- **Virtualisation:** a readable `/dev/kvm` gives `virt_type=kvm`. Without it,
  Hagistack falls back to `qemu` software emulation, which is 10–50× slower.
- **SELinux: the host is switched to permissive.** This is the only mode that has
  been verified.
  - Hagistack sets `httpd_can_network_connect`.
  - It then runs `setenforce 0` and writes `SELINUX=permissive` to
    `/etc/selinux/config`, so the change survives a reboot.
  - If SELinux is `Disabled`, it is reported and left alone. `Disabled` is not
    the verified configuration.
  - **Enforcing mode has not been verified.** The SELinux policy RDO ships for
    OpenStack (`openstack-selinux`) is published only in RDO's OpenStack
    component repositories, and Hagistack does not enable those.
- **The 2026.1 RPMs**: nothing to prepare. `hagistack` downloads, builds or
  unpacks them (see [RPM sources](#rpm-sources)). `--rpm-source build` needs
  about 30 GB of extra disk, internet access to the build inputs, and hours.
- **Internet access for dependency repositories.** Hagistack adds the following:
  - EPEL 10, and it enables CRB;
  - the CentOS Stream 10 NFV SIG mirror, for Open vSwitch and OVN;
  - RDO's EL10 third-party dependency repositories (Python libraries,
    RabbitMQ/Erlang);
  - `download.cirros-cloud.net` for the first guest image, unless you pass
    `--image-file`.

**Network**

- **Management IP.** This is the address the services and the other nodes use.
  By default it is the source address of the route to `8.8.8.8`. Override it with
  `--mgmt-ip`.
- **A provider NIC (`--ext-nic`).** It must exist on the host. Hagistack **does not
  attach it to the provider bridge** (see [Known limitations](#known-limitations)).
- **Provider network values:** a CIDR, a gateway inside it, and a floating-IP
  range inside it.
- **Hostnames.** Each node needs a **distinct short hostname**. Nova's host name
  and the OVN chassis name are both set to the short hostname, and they have to
  match for ports to bind.

**For a second node**

- Rocky Linux 10.2 x86_64. It must run the **same RPM set** as the controller;
  `compute-add` checks this and stops otherwise.
- The ability to reach the controller's management IP on these TCP ports:
  - 5000 (Keystone)
  - 9292 (Glance)
  - 8778 (Placement)
  - 9696 (Neutron API)
  - 8775 (Nova metadata, for the node's metadata agent)
  - 5672 (RabbitMQ)
  - 6642 (OVN southbound)
  - 11211 (memcached)
- Geneve tunnels between the nodes use **UDP 6081**, in both directions. This
  port is not checked.
- Hagistack configures no host firewall. If `firewalld` is active (it is on the
  Rocky Linux images of some clouds), open the ports yourself, for example:

  ```sh
  # on the controller
  sudo firewall-cmd --permanent --add-port={5000,9292,8778,9696,8775,5672,6642,11211}/tcp --add-port=6081/udp
  # on each compute node
  sudo firewall-cmd --permanent --add-port=6081/udp
  # on both
  sudo firewall-cmd --reload
  ```

  Limit the sources to the management network where you can.
- **The same MTU on every node's management interface.** Neutron sizes tenant
  networks from the controller's (`global_physnet_mtu`, set by Hagistack); a
  node with a smaller MTU drops full-size guest packets in the tunnel. A
  network keeps the MTU it was created with; a later change applies to new
  networks only.
- **Synchronised clocks** (chronyd or another NTP client) on every node.

## Installation model

```text
                         hagistack (one script, on each node)
                         ─────────────────────────────────────
 --rpm-source github ─┐
 --rpm-source build  ─┼─▶ verified RPM set in /var/lib/hagistack ─▶ file:// repository
 --rpm-source bundle ─┤                                              (priority=1)
 --repo-url URL      ─┘─────────────────────────────────────────▶ your repository
                                                                       │
                     all-in-one │ controller │ compute-add ◀── dnf install
```

**Every OpenStack package comes from the 2026.1 RPM set.** Its repository is
configured with `priority=1`. RDO's OpenStack component repositories
(`delorean-component-*`) carry trunk snapshots, so Hagistack does not add them
to a node, and it warns if one is enabled.

The third-party Python libraries come from RDO's dependency tree, at whatever
versions EL10 has. Those are not OpenStack deliverables. `python3-cliff` and
`python3-requestsexceptions` come from EPEL 10, at the same upstream versions
that 2026.1 pins.

## RPM sources

| `--rpm-source` | For | What happens |
|---|---|---|
| `github` (default) | normal installs | Downloads the release asset named in `rpm-release.lock` and verifies it against the SHA-256, size and RPM-set identity pinned in that file |
| `build` | building from source | Builds the RPMs from Hagistack's own package definitions (`packaging/`) in a disposable Rocky 10.2 container on this host, then verifies the result |
| `bundle` | compute nodes of a controller that built from source | Verifies a tarball made by `hagistack rpm-bundle` against the controller's RPM-set identity |
| `repo-url` | a repository you already run | Uses `--repo-url` as before. Hagistack verifies nothing in this mode |

Rules common to all of them:

- **No silent fallback.** A failed download never starts a build, a failed build
  never downloads, and nothing falls back to "latest".
- **Verified before use.** An RPM set is used only if every RPM matches its
  listing (`RPM-SHA256SUMS`), the set identity (the SHA-256 of that listing)
  is the expected one, the repository metadata matches the files, and
  `rpm -K` passes for each RPM.
- **Re-runs reuse the set.** A verified set is re-checked and reused; nothing is
  downloaded or built twice. A cached set that no longer verifies is moved aside
  (never deleted) and, for `github`, fetched again.
- **One set per cloud.** Each node records its set. A later run with a
  different set stops before installing anything, and a compute node stops if
  its set differs from the controller's.

**`github`: what you trust.** A checksum file published next to a download
proves nothing, because whoever can replace the download can replace the
checksum. The trust anchor is `rpm-release.lock` **in this Git checkout**. It
pins the asset's SHA-256 and size, the identity of the RPM set inside it, and
the `gazpacho.manifest` it was built from. The RPMs are not GPG-signed.

**`build`: building from source.**

```sh
sudo ./hagistack all-in-one --rpm-source build   # plus your settings
# or prepare the RPMs ahead of time, then install later without rebuilding:
sudo ./hagistack rpm-prepare --rpm-source build
```

- No second machine is needed. The build runs in a container
  (`quay.io/rockylinux/rockylinux:10.2`, pinned by digest), so build
  dependencies and RDO's trunk repositories never reach the host. Hagistack
  installs `podman` if it is missing.
- It takes hours. Progress:
  `/var/lib/hagistack/rpm-build/<id>/out/logs/pass1.log`.
- `packaging/build-own.sh` builds a definition again once the packages it
  needs have been built. A second pass runs only for build-dependency failures
  left after that.
- The result is kept in `/var/lib/hagistack/rpm-build/<id>/`, where `<id>`
  identifies the build inputs. The same inputs are never rebuilt.

**`bundle`: reusing a controller's set on compute nodes.**

```sh
# on the controller
sudo ./hagistack rpm-bundle --output /root/hagistack-rpms.tar
# copy the file to the node, then on the node
sudo ./hagistack compute-add --controller-ip 10.0.0.10 \
    --rpm-source bundle --rpm-bundle /root/hagistack-rpms.tar
```

The expected identity is read from the controller's `compute-secrets` file, so a
bundle that is not the controller's set is refused.

## Build the RPM repository

You normally do not run this yourself: `--rpm-source build` builds the RPMs
for you in a container.

**Current method: Hagistack's own package definitions.** By default the build
uses `packaging/`: `packaging/genspec.py` writes each spec from a definition in
`packaging/defs/`, and `packaging/build-own.sh` builds it. No RDO spec file or
other RDO packaging file is used. See `packaging/README.md`.

**Older method: RDO distgit (`build-rpms.sh`).** The rest of this section
describes `build-rpms.sh`, which builds from RDO distgit packaging. It is the
older method; release candidates up to rc4 were built with it. It is kept until
the set built from the own definitions has been accepted. `hagistack
--rpm-source build` does not use it; `build-in-container.sh` uses it only when
`HAGISTACK_PACKAGING=rdo` is set in its environment. The description is for
maintainers and for building on a separate machine.

`build-rpms.sh` builds the packages listed in `gazpacho.manifest`:

- keystone 29.1.0, glance 32.0.0, placement 15.0.0, neutron 28.0.2, nova 33.0.2
  and horizon 25.7.3;
- the OpenStack libraries and clients they need, at their 2026.1 versions;
- ten static-asset and utility packages that Horizon needs and EL10 lacks.

**Where to run it by hand.** On a **disposable Rocky Linux 10.2 x86_64 VM or
container**, never directly on an OpenStack node. It does the following as root:

- installs build dependencies (`sudo dnf builddep`);
- writes `/etc/yum.repos.d/hagistack-gazpacho.repo`;
- adds `exclude=` lines to RDO repository files, if present.

The recorded build ran on a GCE `n2-standard-4` running the stock Rocky Linux
10.2 image.

**Prepare the builder:**

- a user with `sudo`;
- `git`, `curl`, `python3`, `rpm-build`, `rpmdevtools` and `createrepo_c`;
- repositories from which `dnf builddep` can resolve the build dependencies.

`build-rpms.sh` does **not** configure the builder's repositories. The recorded
builds used Rocky BaseOS/AppStream/CRB, EPEL 10 and RDO's EL10 repository files
(`delorean.repo`, `delorean-deps.repo`) for build dependencies.

**Run it:**

```sh
git clone https://github.com/hagix9/hagistack.git
cd hagistack/rocky10.2
./build-rpms.sh --nocheck                 # everything in gazpacho.manifest
./build-rpms.sh --nocheck keystone        # or: only the named packages
```

**What it verifies before building.** Any mismatch **stops the build**. Nothing
falls back to "latest".

- Each distgit is checked out at the exact commit in the manifest, and the
  commit is compared after checkout.
- Each OpenStack tarball must match its SHA-256 digest.
- The spec's `%prep` checks the tarball's GPG signature against the OpenStack
  release key named in the manifest.
- The ten PyPI inputs for Horizon have **no signature**. They are pinned by
  SHA-256 only.
- RDO's packaging text is **not stored in the current tree of this repository**
  (older commits still contain it). It is fetched from the pinned distgit
  commit. Where RDO's master specs do not match the released tarballs,
  `spec-adapt/` applies Hagistack-written rules to it. The SHA-256 of every
  file that is adapted, and of every result, is pinned in the manifest (`SPEC`
  rows) and checked on each build; the rest of a distgit is pinned by its
  commit. An input that is not the reviewed one, an input
  that is already adapted, or a rule that does not fit stops the build; nothing
  is skipped. See `spec-adapt/RATIONALE.md`. `spec-templates/` holds the one
  template used for the PyPI packages.
- Neutron is the one exception to "the released tarball, unchanged". It also
  applies two upstream Neutron commits that are not in any 2026.1 release:
  `83f1d830` and `91abb5e7`. They fix a race in which the OVN maintenance worker
  could run indefinitely without its database lock. These two patch files are
  the only third-party source files in the current tree. They are
  Apache-2.0, kept in `third-party/neutron/` with the licence text and a notice,
  and pinned by SHA-256 (`PATCH` rows). The Neutron RPMs are therefore release
  `2` (`28.0.2-2`). `tests-neutron-maintenance-lock.py` checks the fix.
- Five of the PyPI sdists (jQuery, jQuery Migrate, quicksearch, TableSorter,
  jQuery UI) carry no licence file. Their upstream licence texts are kept in
  `third-party/licenses/` (see its `NOTICE.md`), pinned by SHA-256 (`LICENSE`
  rows) and installed in those RPMs as `%license` documents.
- `openstack-dashboard` does not ship the copies of the XStatic libraries that
  the build-time `collectstatic` makes, nor the compressed bundles made from
  them (spec-adapt rule `horizon`). Its httpd drop-in rebuilds both from the
  installed XStatic packages before httpd starts, as it always did. The
  release-candidate script checks both points on the built RPMs, and copies
  `THIRD_PARTY_NOTICES.md` into the candidate.

**Outputs.**

| What | Where |
|---|---|
| RPMs and repository metadata (`createrepo_c`) | `~/rpmbuild/RPMS/`. Set `REPO_PUBLISH_DIR` to publish into another directory, for example an existing repository you are adding packages to |
| Build logs | `~/epoxy-build/logs/`. Override the base directory with `WORK` |
| Build-environment lock: every RPM on the builder | `~/epoxy-build/build-env.lock` |

The script exits non-zero if any package failed. `--publish` re-runs only the
repository step. `--lock` rewrites only the lock file.

**`%check` status.**

- `--nocheck` skips the packages' test suites. **The x86_64 RPMs that were
  verified were built with `--nocheck`, so no `%check` was run for them.**
- Without `--nocheck` the suites run. Some are very large: about 121,000 tests
  for os-ken and 21,000 for neutron.

`epoxy.manifest` and `build-keystone-epoxy.sh` are records of an earlier 2025.1
build and are not used. `build-rpms.sh --manifest epoxy.manifest` stops for the
packages that have 2026.1 rules in `spec-adapt/`, because those rules are not
valid for 2025.1 specs. `probe-repos.sh` re-runs the read-only check for
published EL10 OpenStack repositories. Its messages refer to sections of an
earlier version of this README, which is available in the Git history.

## Use your own repository (`--repo-url`)

`--repo-url` becomes the `baseurl` of `/etc/yum.repos.d/hagistack-gazpacho.repo`
on each node. The node must be able to resolve `openstack-keystone` from it,
and the installer checks that before continuing. Two forms work:

- **A local directory.** Copy the whole published directory, including
  `repodata/`, to every node. Then pass it as a file URL:

  ```sh
  # on the builder
  rsync -a ~/rpmbuild/RPMS/ NODE:/opt/hagistack-repo/
  # on the node
  --repo-url file:///opt/hagistack-repo
  ```

- **An HTTP(S) server.** Serve the directory and pass its URL:
  `--repo-url https://repo.example.internal/hagistack-gazpacho/`

The repository is configured with `gpgcheck=0`, **so the RPMs are not signed**.
The dependency repositories Hagistack adds also have `gpgcheck=0`. The integrity
of your repository depends on how you copy or serve it.

## Configuration

Settings come from the **command line** or a **config file**. The command line
wins.

- **Config file.** Hagistack uses the file named by `--env-file`. Without that
  option, it takes the first of these that exists:
  1. `./hagistack.env`
  2. `hagistack.env` next to the script
  3. `/etc/hagistack/hagistack.env`
- **The file format** is the same as on Ubuntu. It is parsed and never executed.
  Only blank lines, `#` comments and `KEY=VALUE` lines for the keys below are
  allowed. Values may contain only letters, digits and `. _ - : / @ + =`.
- **Do not put passwords in the config file.**
- **Environment variables are not read** by the Rocky script. Use options or the
  file.

| Option | Key | Required | Default |
|---|---|---|---|
| `--rpm-source SRC` | `RPM_SOURCE` | | `github`; `repo-url` if `--repo-url` is given; on a deployed host, the recorded source |
| `--repo-url URL` | `REPO_URL` | with `--rpm-source repo-url` | — (`http(s)://…` or `file:///…`) |
| `--rpm-bundle PATH` | `RPM_BUNDLE` | with `--rpm-source bundle` | — |
| `--rpm-set-sha256 HEX` | `RPM_SET_EXPECTED` | | read from compute-secrets on `compute-add` |
| `--rpm-lock-file PATH` | `RPM_LOCK_FILE` | | `rocky10.2/rpm-release.lock` (for testing a mirror) |
| `--build-image REF@sha256:…` | `BUILD_IMAGE` | | the pinned Rocky 10.2 image |
| `--ext-nic NAME` | `EXT_NIC` | all-in-one, controller | — |
| `--provider-cidr CIDR` | `PROVIDER_CIDR` | all-in-one, controller | — |
| `--provider-gateway IP` | `PROVIDER_GATEWAY` | all-in-one, controller | — |
| `--floating-start IP` | `FLOATING_START` | all-in-one, controller | — |
| `--floating-end IP` | `FLOATING_END` | all-in-one, controller | — |
| `--tenant-cidr CIDR` | `TENANT_CIDR` | | `10.10.10.0/24` |
| `--dns-server IP` | `DNS_SERVER` | | the provider gateway |
| `--provider-physnet NAME` | `PROVIDER_PHYSNET` | | `physnet1` |
| `--provider-bridge NAME` | `PROVIDER_BRIDGE` | | `br-ex` |
| `--image-name NAME` | `IMAGE_NAME` | | `cirros-0.6.3-x86_64` |
| `--image-url URL` | `IMAGE_URL` | | the CirrOS 0.6.3 download URL |
| `--image-sha256 HEX` | `IMAGE_SHA256` | set it whenever you change the URL | the published CirrOS digest |
| `--image-file PATH` | `IMAGE_FILE` | | — (use a local file instead of downloading) |
| `--controller-ip IP` | `CONTROLLER_IP` | remote compute-add | — |
| `--local` | — | | add the hypervisor to this controller (compute-add only) |
| `--mgmt-ip IP` | `MGMT_IP` | | autodetected |
| `--virt-type kvm\|qemu` | `VIRT_TYPE` | | autodetected from `/dev/kvm` |
| `--region-name NAME` | `REGION_NAME` | | `RegionOne` |

`--provider-physnet` and `--provider-bridge` work, even though `--help` does not
list them.

An example `hagistack.env` (the values are placeholders):

```sh
RPM_SOURCE=build
EXT_NIC=eth1
PROVIDER_CIDR=192.0.2.0/24
PROVIDER_GATEWAY=192.0.2.1
FLOATING_START=192.0.2.100
FLOATING_END=192.0.2.200
```

## Preflight check

```sh
cd hagistack/rocky10.2
sudo ./hagistack all-in-one --check --rpm-source build \
    --ext-nic eth1 --provider-cidr 192.0.2.0/24 --provider-gateway 192.0.2.1 \
    --floating-start 192.0.2.100 --floating-end 192.0.2.200
```

`--check` runs preflight only and **changes nothing**. It checks the following:

- the OS and architecture;
- the management IP;
- that the provider NIC exists;
- the provider addresses (the gateway and the floating range inside the CIDR);
- the tenant CIDR, the DNS server and the region;
- `virt_type`;
- the RPM source settings, and whether this command is allowed on this host's
  recorded role;
- disk and memory.

It then prints every resolved setting and its source.

`--check` does **not** check the following, which are checked later when the
installer reaches them:

- whether the RPM set can be downloaded, built or unpacked: done in the RPM
  source phase;
- whether `--repo-url` works: checked in the repository phase;
- for `compute-add`, whether the controller's ports are reachable: checked in
  the compute preflight.

## All-in-one installation

```sh
sudo ./hagistack all-in-one --rpm-source build   # plus your settings
# once a release is published, simply:
sudo ./hagistack all-in-one                      # plus your settings
```

The phases run in this order:

1. preflight
2. RPM source (download, build or unpack, then verify)
3. repositories
4. SELinux
5. secrets
6. packages
7. MariaDB
8. RabbitMQ
9. memcached
10. Keystone
11. Glance
12. Placement
13. OVS/OVN
14. Neutron
15. Nova
16. nova-compute
17. initial resources
18. Horizon

Where the APIs run:

- **Web server (`httpd`, mod_wsgi):** Keystone, Placement, Neutron's API, and
  Nova's compute and metadata APIs.
- **Its own unit:** Glance.
- **Disabled:** the packaged units that name binaries 2026.1 no longer ships
  (`neutron-server` and Nova's API units).

The closing banner shows where the admin credentials are, the dashboard URL,
and the exact commands for adding a compute node.

**What all-in-one creates.** Each resource is show-or-create by name.

| Resource | Details |
|---|---|
| Flavor | `m1.tiny`: 1 vCPU, 256 MiB RAM, 1 GiB disk |
| Image | `cirros-0.6.3-x86_64`. It is verified against its SHA-256 digest before upload, and tagged with that digest |
| External network | `hagistack-provider`: flat, external, on `physnet1`. Its subnet holds the floating range and has no DHCP |
| Tenant network | `hagistack-tenant`, with subnet `hagistack-tenant-subnet` |
| Router | `hagistack-router`: gateway on the provider network, plus an interface on the tenant subnet |
| Security group rules | SSH and ICMP on the admin project's `default` group |
| Keypair | `hagistack-key`, generated by Nova. The private key is `/etc/hagistack/hagistack-key`, mode `0600` |

## Controller-only installation, then a local hypervisor

```sh
sudo ./hagistack controller --rpm-source build   # plus the same settings as all-in-one
```

`controller` runs every all-in-one phase except nova-compute: Keystone, Glance,
Placement, Nova API/scheduler/conductor, Neutron with OVN (the controller is
the gateway chassis), Horizon and the initial resources. It does not install
`openstack-nova-compute`, `libvirt` or `qemu-kvm`. **Guests cannot boot until a
compute node exists**; that is expected.

To add the hypervisor to the same host later:

```sh
sudo ./hagistack compute-add --local
```

It uses the RPM set, management IP and region recorded on the controller, runs
no controller phase again (credentials, configuration and data are untouched),
installs the hypervisor packages, starts libvirt and nova-compute, waits for
this host to be `up` and maps it into the cell. The host is then recorded as
`all-in-one`.

What may run on a host that is already deployed:

| Recorded role | `all-in-one` | `controller` | `compute-add --local` | remote `compute-add` |
|---|---|---|---|---|
| controller | yes (adds the hypervisor) | yes (re-run) | yes | refused |
| all-in-one | yes (re-run) | refused | yes (re-run) | refused |
| compute | refused | refused | refused | yes (re-run) |

The role is recorded in `/etc/hagistack/deployment.env`. Hagistack never
removes a service.

## Add a compute node

Run each step on the machine shown. Repeat steps 1–5 for every node.

**1. On the controller:** write the credentials a compute node needs to a file.
The command refuses to write to a terminal.

```sh
(umask 077; sudo ./hagistack compute-secrets > compute-secrets.env)
```

Your shell, not `hagistack`, creates `compute-secrets.env`, so its mode comes
from your umask. The `umask 077` above makes it readable by you only.

The file holds exactly these five credentials, plus the controller's RPM-set
identity (`RPM_SET_SHA256`, not a secret):

- `RABBIT_PASS`
- `NOVA_SERVICE_PASS`
- `PLACEMENT_SERVICE_PASS`
- `NEUTRON_SERVICE_PASS`
- `METADATA_PROXY_SECRET`

It holds no database password and no admin password.

**2. Copy the file to the new node over a secure channel,** then delete the
controller's copy:

```sh
scp compute-secrets.env NODE:/tmp/
shred -u compute-secrets.env
```

**3. On the new node:** install the credentials.

```sh
sudo install -d -m 0700 /etc/hagistack
sudo install -o root -g root -m 0600 /tmp/compute-secrets.env /etc/hagistack/secrets.env
shred -u /tmp/compute-secrets.env
```

**4. On the new node:** run `compute-add`.

```sh
cd hagistack/rocky10.2
# controller installed from the published release (github):
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP
# controller built from source: reuse its RPMs instead of building again
#   (on the controller: sudo ./hagistack rpm-bundle --output /root/hagistack-rpms.tar)
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP \
    --rpm-source bundle --rpm-bundle /root/hagistack-rpms.tar
# controller installed with --repo-url:
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP --repo-url URL
```

`compute-add` never generates secrets. It stops if `/etc/hagistack/secrets.env`
is missing, or if it lacks a valid `RPM_SET_SHA256` (regenerate it on the
controller with this version). It checks that the controller's ports are
reachable **before** it changes anything else, and it stops before installing
packages if this node's RPM set is not the controller's. It also stops, without
starting nova-compute, if any Nova database connection is still in effect on
the node (in `nova.conf` or any other file nova-compute reads).

The node gets no database access: the database connection keys in `nova.conf`
are commented out. It gets no admin credential and no provider bridge mapping.

**5. Back on the controller:** map the new host into the cell.

```sh
sudo ./hagistack discover-hosts
```

## Verify the deployment

```sh
sudo ./hagistack status
```

`status` shows the following:

- the phase markers;
- the SELinux mode now and at boot, and what Hagistack did to it;
- the state of every service unit.

Its `stage` and `unverified` lines are out of date (see
[Troubleshooting](#troubleshooting)).

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

**Horizon sign-in test.** `tests-horizon-login.sh` checks a real admin sign-in.
It passes only if all of the following hold:

- the login POST redirects;
- a session cookie is issued;
- the protected pages render for `admin`;
- two negative cases fail as they should.

The password is read from `/etc/hagistack/admin-openrc` and never appears on a
command line.

```sh
sudo ./tests-horizon-login.sh
# another address:
sudo HZ_URL=http://MGMT_IP/dashboard ./tests-horizon-login.sh
```

Exit status `0` means PASS, `1` means FAIL, and `2` means the script could not
run.

## Horizon

- **URL:** `http://MGMT_IP/dashboard/`, served by `httpd` on port 80.
- **User:** `admin`. The password is `OS_PASSWORD` in `/etc/hagistack/admin-openrc`.
- **Settings:** Hagistack appends a marked block to
  `/etc/openstack-dashboard/local_settings`. The static assets are rebuilt only
  when that block changes.
- **httpd drop-in:** Hagistack adds one that allows writes to
  `/usr/share/openstack-dashboard`. The dashboard package's start-up steps need
  it under `ProtectSystem`.
- **`ALLOWED_HOSTS`:** `['*']`.
- **Console tab:** does not work. The noVNC proxy is not installed.

**Verified** on GCE on 2026-09-29, with these results:

- the login page returned 200;
- the POST returned 302;
- a session cookie was issued;
- four protected pages returned 200 for `admin`, without the login form;
- re-running `all-in-one` rebuilt nothing and restarted nothing, and the
  sign-in still worked.

That result came from the first version of `tests-horizon-login.sh`. The current,
stricter version has been checked against a local fixture only. **It has not
yet been run against a real Horizon.**

## Re-running Hagistack

`all-in-one` and `compute-add` are designed to be run again.

- On the verified all-in-one node, two consecutive runs exited 0. They skipped
  no phase, restarted no unit, and did not rebuild the dashboard assets.
- A second `compute-add` also exited 0 and restarted nothing.

On a re-run:

- **Secrets:** existing secrets are reused, never rotated.
- **Databases:** never dropped.
- **Configuration:** files are edited key by key, and a service restarts only
  when its configuration is newer than its running process.
- **Initial resources:** show-or-create by name.
- **Repository files:** rewritten only when they differ.

Hagistack does **not** roll back. Fix the cause of a failure and run the same
command again.

A re-run is not a reconfiguration tool. Resources and endpoints that already
exist are left in place.

## Command reference

```text
sudo ./hagistack all-in-one  [rpm options] [options]
sudo ./hagistack controller  [rpm options] [options]   no hypervisor
sudo ./hagistack all-in-one  --check [options]         preflight only; changes nothing
sudo ./hagistack compute-add --local                   on a controller: add the hypervisor
sudo ./hagistack compute-add --controller-ip IP [rpm options] [options]
sudo ./hagistack compute-secrets > FILE                controller; refuses a terminal
sudo ./hagistack rpm-bundle --output FILE              controller; its RPM set as a tarball
sudo ./hagistack rpm-prepare [rpm options]             prepare and verify the RPMs only
sudo ./hagistack discover-hosts                        controller; map new compute hosts
sudo ./hagistack status                                role, RPM set, phases, SELinux, services
./hagistack --help | --version

rpm options: --rpm-source github|build|bundle|repo-url, --repo-url URL,
             --rpm-bundle FILE, --rpm-set-sha256 HEX, --rpm-lock-file PATH,
             --build-image REF@sha256:...
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
| other non-zero | A command failed and the run stopped at that point |
| 4 | The run reached the end, but a phase was skipped because a service it needs was unreachable. The deployment is **incomplete**. Fix the cause and re-run |

## Sensitive and generated files

| Path | Contents | Mode |
|---|---|---|
| `/etc/hagistack/` | Hagistack's configuration directory | `0700` |
| `/etc/hagistack/secrets.env` | Every generated credential, including the Horizon secret key. On a compute node, only the five delivered keys | `0600` |
| `/etc/hagistack/admin-openrc` | Admin credentials for the `openstack` CLI | `0600` |
| `/etc/hagistack/hagistack-key` | Private key of the `hagistack-key` keypair | `0600` |
| `/etc/hagistack/deployment.env` | This host's role, addresses and RPM-set identity. No secrets | `0600` |
| `/var/lib/hagistack/state/` | Phase markers, plus the record of what was done to SELinux | — |
| `/var/lib/hagistack/rpms/` | Verified RPM sets from `github` and `bundle` | — |
| `/var/lib/hagistack/rpm-build/` | Source builds: work area and verified result per build-input id | — |
| `/etc/yum.repos.d/hagistack-*.repo` | The repositories Hagistack added | — |
| `/etc/selinux/config` | Set to `SELINUX=permissive` | — |
| `./hagistack.env` | Your settings. It must not contain passwords | — |

## Troubleshooting

- **"no published RPM release is pinned".** No release has been published for
  this checkout yet. Use `--rpm-source build`, or `--repo-url` with a
  repository you have.
- **The download or a verification fails.** Nothing was installed. Hagistack
  does not fall back to building; fix the network or the mirror and re-run, or
  choose `--rpm-source build` yourself.
- **"Switching the package set of a running cloud is an upgrade".** This host
  was deployed from a different RPM set. Hagistack does not upgrade.
- **The repository "does not offer openstack-keystone"** (`--repo-url`). The URL
  must point at a directory that has `repodata/`, meaning `createrepo_c` has
  run over it. It must also be readable from this node.
- **A warning that `delorean-component-*` repositories are enabled.** Disable
  them:

  ```sh
  dnf config-manager --set-disabled 'delorean-component-*'
  ```

  With them enabled, the install is no longer a single OpenStack release.
- **Guests fail with "Refusing to bind port … no OVN chassis for host".** The
  node's Nova host name and its OVN chassis name disagree. Hagistack sets both
  to the short hostname. Check that every node has a distinct, stable short
  hostname, then re-run.
- **A run stops without an `error:` line.** The Rocky script does not always
  print the line where it stopped. The last `==>` step in the output is the
  phase that failed.
- **`compute-add` stops: "the controller is not reachable on every port".**
  No packages were installed. Check the listed ports on the controller, and
  check any firewall between the two nodes.

## Verified environment

Google Compute Engine, 2026-09-29:

- **Image:** stock `rocky-linux-10` (Rocky 10.2).
- **Virtualisation:** nested virtualisation, `virt_type=kvm`.
- **Builder:** an n2-standard-4, deleted afterwards.
- **node1:** `all-in-one` on an n2-standard-4 with 60 GB of disk.
- **node2:** `compute-add` on an n2-standard-2 with 40 GB of disk.
- **SELinux:** permissive.

Verified:

- the real `dnf install` completed;
- every phase completed with none skipped;
- token-authenticated calls to Keystone, Glance, Placement, Neutron and Nova;
- two OVN chassis;
- both nodes `up` in the compute service and hypervisor lists;
- a guest ACTIVE on node1 (18 s) and on node2 (12 s);
- cloud-init completed on node1;
- two guests on different nodes pinged each other, and the packets were
  captured on the Geneve tunnel;
- Horizon admin sign-in;
- re-runs on both nodes exited 0 and restarted nothing.

Horizon was added last. After it was added, node1 was re-checked: the other
services still answered, and a guest still reached ACTIVE.

**2026-11-09 (0.2.0-rocky, implementer's acceptance, not yet independently
audited):** on four Rocky 10.2 GCE VMs — `--rpm-source build` (195 RPMs built in
a container on the host), `controller` followed by `compute-add --local`,
`all-in-one --repo-url`, and two remote `compute-add` nodes (one with
`--rpm-source bundle`, one with `--rpm-source github` against a mock release
server). Guests booted on every hypervisor and pinged each other across nodes;
re-runs exited 0 and restarted nothing. A real GitHub Release has not been
published or tested. Details:
[acceptance/ROCKY_INSTALLER_COMPLETION_ACCEPTANCE_2026-11-09.md](../acceptance/ROCKY_INSTALLER_COMPLETION_ACCEPTANCE_2026-11-09.md).

## Known limitations

**Not included**

- **Provider NIC attachment.** The provider NIC is **never attached** to
  `br-ex`. Provider networks and floating IPs reach no physical LAN until you
  attach a NIC yourself.
- **Other services.** Cinder (volumes), Swift and other OpenStack services are
  not installed.
- **noVNC.** The console proxy is not installed.
  If you install `openstack-nova-novncproxy` yourself, note that it only
  *recommends* `novnc` (a weak dependency). A plain `dnf install` may install
  `novnc` with it, but with `install_weak_deps=False` it does not. The proxy
  serves `/usr/share/novnc` by default and exits if that directory is missing,
  so install `novnc` as well in that case. If you point the proxy at another
  directory instead (for example `OPTIONS="--web <dir>"` in
  `/etc/sysconfig/openstack-nova-novncproxy`), that directory's content is
  served.
- **SELinux policy.** No OpenStack SELinux policy is installed, and the host is
  switched to permissive.
- **Firewall.** No host firewall is configured. The APIs, RabbitMQ, the OVN
  southbound database and memcached listen on the management network, so keep
  the nodes on a trusted network.
- **Package signatures.** The RPMs are not signed, and the added repositories
  use `gpgcheck=0`.

**Not verified**

- **SELinux enforcing.**
- **`%check`.** The package test suites were not run for the x86_64 RPMs.
- **Networking beyond the tenant network:** a physical-LAN path, or reaching
  floating IPs from outside the host.
- **Live migration.**
- **Three or more nodes.**
- **Other EL10 distributions.**
- **Hosts with an active firewall.**

**Not supported**

- architectures other than x86_64.
