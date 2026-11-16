---
title: Install
description: Preflight, the all-in-one installation, checking services with status, and signing in to Horizon.
sidebar:
  order: 2
---

This page assumes [Before you install](/en/quickstart/prepare/) is done.
Run every command in the `hagistack/rocky10.2` directory.

## 6. Run preflight

```bash
sudo ./hagistack all-in-one --check
```

- **What it does:** checks the settings and the host, and prints every resolved setting and where it came from (command line, file, autodetected). **It changes nothing.**
- **What it checks:** OS and architecture, the management IP, that the provider NIC exists, the provider addresses (gateway and floating range inside the CIDR), the tenant CIDR, DNS, region, `virt_type`, the RPM source, disk and memory.
- **Expected result:** it ends without an error and prints the settings.
- **What it does not check:** whether the RPMs can be downloaded (checked in the RPM-source phase of the installation).

Without a configuration file, pass the settings as options:

```bash
sudo ./hagistack all-in-one --check \
    --ext-nic eth1 --provider-cidr 198.51.100.0/24 --provider-gateway 198.51.100.1 \
    --floating-start 198.51.100.100 --floating-end 198.51.100.200
```

## 7. Install all-in-one

```bash
sudo ./hagistack all-in-one
```

- **What it does:** downloads and verifies the release RPMs from GitHub Releases and installs OpenStack 2026.1.
- **Time:** about 8 minutes on the verified all-in-one node (n2-standard-8), plus downloading the RPMs (about 108 MB).
- **Expected result:** it ends with `every phase completed` and prints where the credentials are, the dashboard URL and the commands to add a compute node.

The phases run in this order:

1. preflight
2. RPM source (download; SHA-256, size, RPM-set identity and `rpm -K` checks)
3. repositories
4. SELinux
5. secrets (passwords are generated)
6. packages
7. MariaDB → RabbitMQ → memcached
8. Keystone → Glance → Placement → OVS/OVN → Neutron → Nova → nova-compute
9. initial resources
10. Horizon

:::tip[If it fails]
HAGISTACK does not roll back. Fix the cause and run the same command again; a re-run is safe.
Existing secrets are reused, databases are never dropped, and files change only when their content differs.
The last `==>` line of the output is the phase that failed.
:::

### Initial resources

Each one is created only if a resource with that name does not exist.

| Resource | Details |
|---|---|
| Flavor | `m1.tiny`: 1 vCPU, 256 MiB RAM, 1 GiB disk |
| Image | `cirros-0.6.3-x86_64`, verified against its SHA-256 before upload, public |
| External network | `hagistack-provider`: flat, external, on `physnet1`. Its subnet `hagistack-provider-subnet` holds the floating range and has no DHCP |
| Tenant network | `hagistack-tenant`, with subnet `hagistack-tenant-subnet` |
| Router | `hagistack-router`: gateway on the provider network, interface on the tenant subnet |
| Security group | SSH (TCP 22) and ICMP rules on the admin project's `default` group |
| Key pair | `hagistack-key`. The private key is `/etc/hagistack/hagistack-key`, mode `0600` |

## 8. Check the services with status

```bash
sudo ./hagistack status
```

- **What it does:** shows the completed phases, the SELinux state and the state of every service unit.
- **Expected result:** every line under `services` says `active` (MariaDB, RabbitMQ, memcached, httpd, Glance, OVN, Open vSwitch, the Neutron workers, Nova conductor, scheduler and compute, libvirtd).

:::note
The `stage` and `unverified` lines of `status` are out of date. Use it for the state of the services.
:::

## 9. Find the Horizon URL

Horizon (the dashboard) runs on port 80 of the management IP:

```text
http://MGMT_IP/dashboard/
```

Example: `http://192.0.2.10/dashboard/` (a documentation address).
The end of the installation output also shows it as `Dashboard :`.

:::caution
Horizon is served over HTTP, and `ALLOWED_HOSTS` is `['*']`. HAGISTACK configures no firewall: keep the management network trusted.
:::

## 10. Find the admin user and password

- **User:** `admin`
- **Password:** `OS_PASSWORD` in `/etc/hagistack/admin-openrc`

```bash
sudo grep '^export OS_PASSWORD=' /etc/hagistack/admin-openrc
```

:::danger[Keep the password private]
Only root can read this file (mode `0600`).
Do not show the password in screen shares, screenshots, logs or chats.
:::

## 11. Sign in to Horizon

1. Open `http://MGMT_IP/dashboard/` in a browser.
2. Enter `admin` and the password above, and **Sign In**.
3. Check that the project at the top left is `admin`.

If you cannot sign in, see [Troubleshooting](/en/operations/troubleshooting/).
To check the sign-in from the command line, use the bundled `tests-horizon-login.sh`:

```bash
sudo ./tests-horizon-login.sh
```

Exit status `0` means PASS.

Next: [Your first VM](/en/quickstart/first-vm/).
