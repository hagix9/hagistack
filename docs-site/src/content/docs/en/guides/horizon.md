---
title: Horizon guide
description: Signing in to Horizon (the OpenStack dashboard) and working with images, flavors, instances, networks, floating IPs, security groups and key pairs.
sidebar:
  order: 1
---

Horizon is the browser dashboard for OpenStack. HAGISTACK shows it as `Hagistack Dashboard`.

:::note[What this page is based on]
The HAGISTACK acceptance tests verified the admin sign-in, the protected pages, and that the logos and static files load.
Creating instances and assigning floating IPs were verified **with the CLI**.
The screen steps on this page follow Horizon 2026.1's standard menus and were not verified screen by screen. Screenshots of the real screens are not included yet.
:::

:::caution[The console (noVNC) does not work in the current release]
The release `rocky10.2-rpms-2026.1` does not install the noVNC console proxy, so an instance's **Console** tab does not work.
Use the **Log** tab (the same as `openstack console log show`) for the boot log.
noVNC support is in development ([noVNC console (in development)](/en/development/novnc/)).
:::

## Sign in

| Item | Value |
|---|---|
| URL | `http://MGMT_IP/dashboard/` |
| Domain | `Default` (no field is shown) |
| User name | `admin` |
| Password | `OS_PASSWORD` in `/etc/hagistack/admin-openrc` |

The language follows the browser's setting. Menu names below are the English ones.

## Choose the project

The project name at the top left switches the project you work in. HAGISTACK's initial resources (tenant network, key pair, security group rules) are in the **admin** project.

## Images

**Project → Compute → Images**

- `cirros-0.6.3-x86_64` is registered as a public image.
- **Create Image** uploads an image file such as qcow2.

## Flavors

**Admin → Compute → Flavors**

- `m1.tiny` (1 vCPU, 256 MiB RAM, 1 GiB disk) exists.
- Only administrators can create and delete flavors.

## Key pairs

**Project → Compute → Key Pairs**

- `hagistack-key` exists. Its private key is `/etc/hagistack/hagistack-key` on the host; Horizon cannot download it.
- **Create Key Pair** creates a new pair; its private key is downloaded once, at that moment.

## Launch an instance

**Project → Compute → Instances → Launch Instance**

| Tab | Setting |
|---|---|
| Details | instance name (for example `demo2`) |
| Source | boot source **Image**, allocate `cirros-0.6.3-x86_64`. HAGISTACK installs no Cinder (volumes): if an option to create a volume is shown, choose **No** |
| Flavor | `m1.tiny` |
| Networks | `hagistack-tenant` (not `hagistack-provider`) |
| Security Groups | `default` |
| Key Pair | `hagistack-key` |

**Launch Instance** starts it. It is up when **Status** is `Active` and **Power State** is `Running`.

## Networks

**Project → Network → Networks / Routers / Network Topology**

- `hagistack-tenant` (tenant) and `hagistack-provider` (external, shared) exist.
- **Network Topology** shows the router `hagistack-router` joining the tenant and provider networks.

## Assign a floating IP

**Project → Network → Floating IPs → Allocate IP To Project**

1. Choose the pool `hagistack-provider` and allocate.
2. **Associate** it with the instance's port.

**Associate Floating IP** in the instance list does the same.
Whether a floating IP is reachable from a physical LAN depends on your setup; see [Your first VM](/en/quickstart/first-vm/#15-assign-a-floating-ip).

## Security groups

**Project → Network → Security Groups**

- The admin project's `default` group has ingress rules for SSH (TCP 22) and ICMP.
- **Manage Rules → Add Rule** adds rules. Allow only the traffic you need.

## Start, stop and delete instances

Use the menu at the right of the instance list.

| Action | Menu | CLI |
|---|---|---|
| Stop | Shut Off Instance | `openstack server stop` |
| Start | Start Instance | `openstack server start` |
| Reboot | Soft / Hard Reboot Instance | `openstack server reboot [--hard]` |
| Delete | Delete Instance | `openstack server delete` |
| Boot log | instance name → Log | `openstack console log show` |

:::danger
Deletion cannot be undone.
:::

## Check an instance

Click the instance name: **Overview** shows its status, flavor, IP addresses and creation time.
Administrators see every project's instances, and the compute host each runs on, under **Admin → Compute → Instances**.
