---
title: Neutron (networking)
description: Networks, subnets, routers, floating IPs, security groups and agents.
sidebar:
  order: 5
---

Neutron manages virtual networks. HAGISTACK uses ML2/OVN.

## Lists

```bash
openstack network list
openstack subnet list
openstack router list
openstack floating ip list
openstack security group list
```

| Command | HAGISTACK's initial state | Horizon |
|---|---|---|
| `network list` | `hagistack-provider` (external, shared), `hagistack-tenant` | Project → Network → Networks |
| `subnet list` | `hagistack-provider-subnet` (floating range, no DHCP), `hagistack-tenant-subnet` | same |
| `router list` | `hagistack-router` | Project → Network → Routers |
| `floating ip list` | (empty until you create one) | Project → Network → Floating IPs |
| `security group list` | a `default` group per project | Project → Network → Security Groups |

## The router

```bash
openstack router show hagistack-router
```

`external_gateway_info` names `hagistack-provider`, and an interface is on the tenant subnet.

## Floating IPs

```bash
openstack floating ip create hagistack-provider
openstack server add floating ip demo1 FLOATING_IP
openstack server remove floating ip demo1 FLOATING_IP
openstack floating ip delete FLOATING_IP
```

:::caution
Whether floating IPs are reachable from a physical LAN depends on the provider NIC. HAGISTACK does not attach it to `br-ex` ([Your first VM](/en/quickstart/first-vm/#15-assign-a-floating-ip)).
:::

## Security groups

```bash
SG=$(openstack security group list --project admin -f value -c ID -c Name | awk '$2=="default"{print $1}')
openstack security group rule list "$SG"
openstack security group rule create --protocol tcp --dst-port 80 --remote-ip 192.0.2.0/24 "$SG"
```

- Every project has a group named `default`, so use the ID.
- Limit the source with `--remote-ip` (the example address is an RFC 5737 documentation address).
- Delete a rule you no longer need with `openstack security group rule delete RULE_ID`.

## Create another tenant network

```bash
openstack network create net2
openstack subnet create --network net2 --subnet-range 10.20.0.0/24 net2-subnet
openstack router add subnet hagistack-router net2-subnet
```

Attached to the existing router, VMs on `net2` can use floating IPs too. Keep the range apart from the existing networks.

## Agents

```bash
openstack network agent list
```

Each node's `OVN Controller agent` (`OVN Controller Gateway agent` on the controller) and `OVN Metadata agent` show `Alive` = `True`.

:::danger
`network delete`, `subnet delete` and `router delete` cannot be undone. A deleted `hagistack-*` initial resource is recreated by a HAGISTACK re-run, but the VMs attached to it lose connectivity.
:::
