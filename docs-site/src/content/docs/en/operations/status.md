---
title: Checking the services
description: HAGISTACK's own status (sudo ./hagistack status), systemd and the OpenStack CLI, and how re-runs behave.
sidebar:
  order: 2
---

## HAGISTACK's own status (hagistack status)

`status` is a HAGISTACK subcommand. It is not the OpenStack CLI (the `openstack` command); it reports the state of a host HAGISTACK deployed.

The `hagistack` script is not on the PATH: run it with `./` from the directory you cloned (`hagistack/rocky10.2`). It needs root.

```bash
cd hagistack/rocky10.2
sudo ./hagistack status
```

It shows:

- the HAGISTACK version, and the target release and OS
- the role (`all-in-one`, `controller`, `compute`), the RPM source and set identity
- the SELinux mode now and at boot, and what HAGISTACK did to it
- the completed phases
- the state of every service unit (`active` and so on)

:::note
Its `stage` and `unverified` lines are out of date.
:::

## systemd

```bash
systemctl status openstack-nova-compute
journalctl -u openstack-nova-compute -n 100
```

The main units:

| Unit | Node |
|---|---|
| `mariadb`, `rabbitmq-server`, `memcached` | controller |
| `httpd` (Keystone, Placement, Neutron API, Nova API, Horizon) | controller |
| `openstack-glance-api` | controller |
| `ovn-northd` | controller |
| `neutron-rpc-server`, `neutron-periodic-workers`, `neutron-ovn-maintenance-worker` | controller |
| `openstack-nova-conductor`, `openstack-nova-scheduler` | controller |
| `ovn-controller`, `openvswitch` | every node |
| `neutron-ovn-metadata-agent` | every node |
| `openstack-nova-compute`, `libvirtd` | every node with a hypervisor |

## The OpenStack CLI

```bash
sudo -i
. /etc/hagistack/admin-openrc
openstack compute service list
openstack hypervisor list
openstack network agent list
```

- `compute service list`: everything `enabled` / `up`
- `hypervisor list`: every compute host `up`
- `network agent list`: every agent `Alive` = `True`

## Re-runs

`all-in-one` and `compute-add` are designed to be run again.

- **Secrets:** reused, never rotated.
- **Databases:** never dropped.
- **Configuration:** edited key by key; a service restarts only when its configuration is newer than its running process.
- **Initial resources:** show-or-create by name.

HAGISTACK does not roll back. Fix the cause of a failure and run the same command again.
A re-run is not a reconfiguration tool: existing resources and endpoints are left as they are.
