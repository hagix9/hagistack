---
title: Before you install
description: Host requirements, the management and provider networks, getting the release, and the configuration file.
sidebar:
  order: 1
---

The quick start has three pages:

1. **Before you install** (this page): check the host, get HAGISTACK, write the configuration file
2. [Install](/en/quickstart/install/): preflight, `all-in-one`, `status`, Horizon sign-in
3. [Your first VM](/en/quickstart/first-vm/): create a VM, floating IP, SSH, stop, start and delete

It is written for OpenStack beginners who know basic Linux. It builds an **all-in-one** host.

## 1. Prepare Rocky Linux 10.2

Use one freshly installed **Rocky Linux 10.2 (x86_64)** host.

- Other EL10 distributions (RHEL, AlmaLinux, CentOS 10) continue with a warning and are **not verified**. Other operating systems and architectures are refused.
- Work as a user who can become root with `sudo`.
- systemd is required.

## 2. Check CPU, memory, disk and NICs

| Item | Requirement | Notes |
|---|---|---|
| Memory | 8 GB or more | Preflight warns below about 7 GB |
| Disk | 20 GB or more free on `/` | The verified all-in-one node had 60 GB |
| Virtualisation | a readable `/dev/kvm` | Without it, `qemu` software emulation is used, 10–50× slower |
| NICs | a management NIC, and an existing interface to name as the provider NIC | The provider NIC is **not attached** to the bridge (see below) |
| Host name | a distinct short host name per node | Used as the Nova host name and the OVN chassis name |
| Clock | synchronised (chronyd or similar) | |
| Internet access | GitHub, EPEL 10, CentOS NFV SIG, RDO dependency repositories, CirrOS | see below |

Check hardware virtualisation:

```bash
ls -l /dev/kvm
grep -cE 'vmx|svm' /proc/cpuinfo
```

KVM is usable if `/dev/kvm` exists and the second command prints 1 or more.
On a cloud VM, nested virtualisation must be enabled (on GCE, for example, a machine type and option that support it).

The installer adds these sources and downloads from the internet:

- `https://github.com/hagix9/hagistack/releases/download/` (the HAGISTACK RPMs, about 108 MB)
- EPEL 10 (it also enables CRB)
- the CentOS Stream 10 NFV SIG (Open vSwitch and OVN)
- RDO's EL10 third-party dependency repositories (Python libraries, RabbitMQ/Erlang)
- `download.cirros-cloud.net` (the first guest image; not needed with `--image-file`)

:::caution[SELinux is switched to permissive]
HAGISTACK switches SELinux to permissive and writes `/etc/selinux/config` so that it stays so after a reboot.
No OpenStack SELinux policy is installed, and enforcing mode is not verified.
:::

## 3. Understand the management and provider networks

HAGISTACK deals with three networks.

| Network | Role | Settings |
|---|---|---|
| **Management network** | OpenStack APIs, database, messaging, traffic between nodes. Horizon opens at this address too | management IP (`--mgmt-ip`; default: the source address of the route to `8.8.8.8`) |
| **Provider network** | the external network `hagistack-provider`; floating IPs come from it | `--provider-cidr`, `--provider-gateway`, `--floating-start`, `--floating-end` |
| **Tenant network** | the private network `hagistack-tenant` VMs attach to | `--tenant-cidr` (default `10.10.10.0/24`) |

:::caution[The provider NIC is not attached to the bridge]
HAGISTACK creates the provider bridge `br-ex` but does **not attach** the NIC named with `--ext-nic` to it.
Until you attach a NIC yourself, the provider network and the floating IPs reach no physical LAN.
Reaching them from a physical LAN is not verified.
[Your first VM](/en/quickstart/first-vm/) shows how to log in to a VM on a single host.
:::

This guide uses these example values:

| Item | Example |
|---|---|
| Management IP | `192.0.2.10` |
| Provider NIC | `eth1` |
| Provider CIDR | `198.51.100.0/24` |
| Provider gateway | `198.51.100.1` |
| Floating-IP range | `198.51.100.100` to `198.51.100.200` |

:::danger[Do not use the example addresses as they are]
`192.0.2.0/24` and `198.51.100.0/24` are **documentation addresses** defined by RFC 5737.
They do not work on a real network. Replace them with the values of your network.
NIC names also differ between hosts (`ip -br link` lists them).
:::

## 4. Get HAGISTACK from the release tag

Clone the release tag `rocky10.2-rpms-2026.1`:

```bash
sudo dnf -y install git
git clone --branch rocky10.2-rpms-2026.1 https://github.com/hagix9/hagistack.git
cd hagistack/rocky10.2
```

The tag contains `rpm-release.lock`. The installer checks the downloaded RPMs against the SHA-256, size and RPM-set identity pinned in it.
Checkouts older than the tag pin no release, and the default source (`github`) stops.

## 5. Write the configuration file

Settings come from the command line or a configuration file; the command line wins.
The file is looked for as `./hagistack.env`, then `hagistack.env` next to the script, then `/etc/hagistack/hagistack.env`.

Create `hagistack/rocky10.2/hagistack.env` (replace the values with yours):

```bash
cat > hagistack.env <<'EOF'
# RPM_SOURCE=github is the default (the published release)
EXT_NIC=eth1
PROVIDER_CIDR=198.51.100.0/24
PROVIDER_GATEWAY=198.51.100.1
FLOATING_START=198.51.100.100
FLOATING_END=198.51.100.200
EOF
```

- Only `KEY=VALUE` lines, blank lines and `#` comments are allowed. The file is parsed, never executed.
- **Do not put passwords in it.** HAGISTACK generates the passwords.
- Environment variables are not read.

The main settings:

| Option | Key | Required | Default |
|---|---|---|---|
| `--ext-nic NAME` | `EXT_NIC` | all-in-one, controller | — |
| `--provider-cidr CIDR` | `PROVIDER_CIDR` | all-in-one, controller | — |
| `--provider-gateway IP` | `PROVIDER_GATEWAY` | all-in-one, controller | — |
| `--floating-start IP` | `FLOATING_START` | all-in-one, controller | — |
| `--floating-end IP` | `FLOATING_END` | all-in-one, controller | — |
| `--mgmt-ip IP` | `MGMT_IP` | | autodetected |
| `--tenant-cidr CIDR` | `TENANT_CIDR` | | `10.10.10.0/24` |
| `--dns-server IP` | `DNS_SERVER` | | the provider gateway |
| `--virt-type kvm\|qemu` | `VIRT_TYPE` | | from `/dev/kvm` |
| `--image-file PATH` | `IMAGE_FILE` | | — (use a local image instead of downloading) |

Every setting is listed under "Configuration" in `rocky10.2/README.md`.

Next: [Install](/en/quickstart/install/).
