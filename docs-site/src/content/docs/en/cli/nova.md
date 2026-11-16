---
title: Nova (VMs)
description: Listing, creating, starting, stopping, rebooting and deleting VMs; compute services and hypervisors; where a VM runs.
sidebar:
  order: 4
---

Nova manages VMs (instances; `server` in the CLI).

## List and inspect VMs

```bash
openstack server list
openstack server list --all-projects --long     # administrators: every project
openstack server show demo1
```

| Item | Value |
|---|---|
| Expected output | name, status (`ACTIVE`, `SHUTOFF`, `ERROR`, ...), networks and addresses, image, flavor |
| Permission | member for your own project's VMs; `--all-projects` needs an administrator |
| Horizon | Project → Compute → Instances (administrators: Admin → Compute → Instances) |

## Create a VM

```bash
openstack server create --flavor m1.tiny --image cirros-0.6.3-x86_64 \
    --network hagistack-tenant --key-name hagistack-key --wait demo1
```

| Option | Meaning |
|---|---|
| `--flavor` | size: CPU, memory, disk |
| `--image` | the image to boot |
| `--network` | the network to attach (the tenant network) |
| `--key-name` | the SSH public key to inject |
| `--security-group` | the security group (default: `default`) |
| `--wait` | wait until `ACTIVE` |

HAGISTACK installs no Cinder (volumes); a VM's disk is created on the compute node's local disk.

## Start, stop, reboot, delete

```bash
openstack server stop demo1
openstack server start demo1
openstack server reboot demo1          # soft reboot
openstack server reboot --hard demo1   # hard reboot
openstack server delete --wait demo1
```

:::danger
`server delete` deletes the VM and its local disk. It cannot be undone.
:::

## Boot log

```bash
openstack console log show demo1
```

Shows cloud-init's output and more. In Horizon, the instance's **Log** tab.

:::note[Console URL]
`openstack console url show --novnc demo1` returns a noVNC console URL, but the release `rocky10.2-rpms-2026.1` installs no noVNC proxy, so it cannot be used ([noVNC console (in development)](/en/development/novnc/)).
:::

## Compute services and hypervisors

```bash
openstack compute service list
openstack hypervisor list
openstack hypervisor show HYPERVISOR_HOSTNAME
```

| Command | Expected output | Permission | Horizon |
|---|---|---|---|
| `compute service list` | `nova-scheduler`, `nova-conductor`, `nova-compute` (per host) `enabled` / `up` | administrator | Admin → System → System Information |
| `hypervisor list` | compute hosts `up` | administrator | Admin → Compute → Hypervisors |

## Where a VM runs

```bash
openstack server show demo1 -c name -c status -c OS-EXT-SRV-ATTR:host
openstack server list --all-projects --host HOSTNAME
```

Only administrators can see `OS-EXT-SRV-ATTR:host`. For how placement works and how to request a host, see [Add a compute node](/en/guides/add-compute/#8-how-vms-are-placed).

## Flavors

```bash
openstack flavor list
openstack flavor create --vcpus 1 --ram 512 --disk 2 m1.small
```

Only administrators can create and delete flavors. `--ram` is in MiB, `--disk` in GiB.
