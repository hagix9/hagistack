---
title: CLI basics
description: Loading the credentials for the OpenStack CLI (the openstack command), output formats, help, and the matching Horizon pages.
sidebar:
  order: 1
---

HAGISTACK installs the `openstack` command (python-openstackclient) on the controller.
The command syntax in this guide was checked against the `--help` of the version the nodes get: **python-openstackclient 9.0.1** (openstacksdk 4.10.0).

## Load the credentials

```bash
sudo -i
. /etc/hagistack/admin-openrc
```

- `/etc/hagistack/admin-openrc` holds the admin user's credentials (readable by root only).
- It sets the Keystone URL (`http://MGMT_IP:5000/v3`), the user `admin`, the project `admin` and so on.
- Check:

```bash
openstack token issue -c expires -c project_id
openstack catalog list
```

`catalog list` shows the identity, image, placement, network and compute services.

:::caution[admin is powerful]
The admin credentials can delete every project's resources. For day-to-day users, create users with narrower roles in [Keystone](/en/cli/keystone/).
:::

## Help and output formats

```bash
openstack help server create      # help for a subcommand
openstack server list -f json      # JSON output
openstack server list -f value -c ID -c Name   # values only, chosen columns
```

| Option | Meaning |
|---|---|
| `-f table` | table (default) |
| `-f json` / `-f yaml` | machine-readable |
| `-f value` | values only (for scripts) |
| `-c COLUMN` | columns to show (repeatable) |

## Example output

Example output on these pages shows the format only and is marked as an example; it is not captured from a real host. IDs, times and host names differ on every installation.

## Destructive operations

`delete`, `remove`, `set --disable` and the like delete or change resources, mostly irreversibly.
Check the name and ID with `list` / `show` first.

## CLI and Horizon

| CLI | Horizon |
|---|---|
| `openstack user list` | Identity → Users |
| `openstack project list` | Identity → Projects |
| `openstack image list` | Project → Compute → Images |
| `openstack flavor list` | Admin → Compute → Flavors |
| `openstack server list` | Project → Compute → Instances |
| `openstack keypair list` | Project → Compute → Key Pairs |
| `openstack network list` | Project → Network → Networks |
| `openstack router list` | Project → Network → Routers |
| `openstack floating ip list` | Project → Network → Floating IPs |
| `openstack security group list` | Project → Network → Security Groups |
| `openstack hypervisor list` | Admin → Compute → Hypervisors |
| `openstack compute service list` | Admin → System → System Information |

Per service: [Keystone](/en/cli/keystone/), [Glance](/en/cli/glance/), [Nova](/en/cli/nova/), [Neutron](/en/cli/neutron/), [Placement](/en/cli/placement/).
