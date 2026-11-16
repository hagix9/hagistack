---
title: Checking the services
description: hagistack status, systemd and the OpenStack CLI, and how re-runs behave.
sidebar:
  order: 2
---

## hagistack status

```bash
sudo ./hagistack status
```

It shows:

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
| `neutron-ovn-metadata-agent` | every node with a hypervisor |
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
