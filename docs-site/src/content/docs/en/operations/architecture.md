---
title: Architecture and networks
description: All-in-one versus controller + compute, the services on each node, and the networks.
sidebar:
  order: 1
---

## All-in-one and controller + compute

| Configuration | Command | What it does |
|---|---|---|
| All-in-one | `all-in-one` | control plane and hypervisor on one host |
| Controller only | `controller` | no hypervisor; VMs cannot boot until a compute node exists |
| Hypervisor added to the controller | `compute-add --local` | makes the controller equivalent to all-in-one (nothing on the controller is reconfigured) |
| Compute node | `compute-add --controller-ip IP` | another host becomes a compute node |

What may run on a host that is already deployed depends on its recorded role:

| Recorded role | `all-in-one` | `controller` | `compute-add --local` | remote `compute-add` |
|---|---|---|---|---|
| controller | yes (adds the hypervisor) | yes (re-run) | yes | refused |
| all-in-one | yes (re-run) | refused | yes (re-run) | refused |
| compute | refused | refused | refused | yes (re-run) |

The role is recorded in `/etc/hagistack/deployment.env`. HAGISTACK never removes a service.

## Services on each node

| Component | Controller / all-in-one | Compute node |
|---|---|---|
| Keystone | httpd (mod_wsgi), port 5000 | — |
| Glance | its own unit, port 9292 | — |
| Placement | httpd, port 8778 | — |
| Nova | API (8774) and metadata API (8775) in httpd; conductor, scheduler | nova-compute, libvirt |
| Neutron | API (9696) in httpd; RPC server, periodic workers, OVN maintenance worker, OVN metadata agent | OVN metadata agent |
| OVN / Open vSwitch | northbound and southbound DBs, ovn-northd, ovn-controller (gateway chassis) | ovn-controller |
| Horizon | httpd, port 80, `/dashboard` | — |
| MariaDB | bound to `127.0.0.1` only | — |
| RabbitMQ, memcached | management network | — |

A compute node **never connects to the database** (the database keys in `nova.conf` are commented out). It has no admin credential and no provider bridge mapping.

## Networks

```text
                 physical network
  ─────────────┬──────────────────────┬─────────────  management network
               │ management IP         │ management IP
       ┌───────┴────────┐     ┌───────┴────────┐
       │ node 1         │     │ node 2         │
       │ controller     │     │ compute        │
       │  br-ex ── (provider NIC not attached)  │
       │  OVN gateway   │     │                │
       │  VMs           │     │  VMs           │
       └────────────────┘     └────────────────┘
          ╲___________ Geneve tunnel (UDP 6081) ___________╱
```

- **Management network:** APIs, RabbitMQ, OVN southbound, memcached, and the Geneve tunnels between nodes.
- **Tenant network (`hagistack-tenant`):** the VMs' virtual network; traffic between nodes goes through the Geneve tunnels.
- **Provider network (`hagistack-provider`):** a flat network mapped `physnet1` → `br-ex`, used for the router's external gateway and floating IPs. The controller is the gateway chassis.
- **Provider NIC:** HAGISTACK attaches no NIC to `br-ex`. Joining the provider network to a physical LAN is up to you and is not verified.
- **MTU:** the tenant networks' MTU comes from the controller's management interface (`global_physnet_mtu`). Give every node's management interface the same MTU.

## Getting and checking the RPMs

```text
 --rpm-source github ─┐
 --rpm-source build  ─┼─▶ verified RPM set in /var/lib/hagistack ─▶ file:// repository (priority=1)
 --rpm-source bundle ─┤
 --repo-url URL      ─┘─────────────────────────────────────────▶ your repository
```

- **github (default):** downloads the GitHub Release asset and checks it against the SHA-256, size and RPM-set identity pinned in `rpm-release.lock` in the Git tag, `RPM-SHA256SUMS`, the repository metadata and `rpm -K`.
- **build:** builds the RPMs from source in a container on the host (hours).
- **bundle:** reuses the controller's RPM set on a compute node.
- **repo-url:** your own repository; HAGISTACK verifies nothing.

A failure never switches to another source. One cloud uses one RPM set.
