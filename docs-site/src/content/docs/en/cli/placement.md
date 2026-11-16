---
title: Placement (resources)
description: Resource providers and allocations, and how to look at them on HAGISTACK.
sidebar:
  order: 6
---

Placement records the resources each compute host has (vCPU, memory, disk) and what VMs use.

- **Resource provider:** one per compute host (node 1, node 2, ...).
- **Inventory:** what a provider has in total (`VCPU`, `MEMORY_MB`, `DISK_GB`).
- **Allocation:** what a VM uses. The Nova scheduler asks Placement which hosts have room.

## Looking at it on HAGISTACK

Placement subcommands such as `openstack resource provider list` come from a separate plugin (osc-placement).
**HAGISTACK does not install it.** Use one of these instead.

### From the hypervisors

```bash
openstack hypervisor list
openstack hypervisor show HYPERVISOR_HOSTNAME
```

The compute hosts and their state.

### Read the Placement API

This is how the acceptance tests checked Placement. In a root shell with the admin credentials:

```bash
URL=$(openstack endpoint list --service placement --interface public -f value -c URL | head -1)
TOKEN=$(openstack token issue -f value -c id)
curl -s -H "X-Auth-Token: $TOKEN" -H 'OpenStack-API-Version: placement 1.0' \
    "$URL/resource_providers" | python3 -m json.tool
```

**Expected result:** `resource_providers` lists one provider per compute host.

:::caution[The token]
`TOKEN` is an admin token, valid until it expires. Keep it out of screen shares and logs.
:::

A provider's inventory, by its `uuid`:

```bash
curl -s -H "X-Auth-Token: $TOKEN" -H 'OpenStack-API-Version: placement 1.0' \
    "$URL/resource_providers/PROVIDER_UUID/inventories" | python3 -m json.tool
```

Horizon has no Placement page. Admin → Compute → Hypervisors summarises the usage per host.
