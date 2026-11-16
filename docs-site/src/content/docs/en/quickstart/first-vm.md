---
title: Your first VM
description: Check the image and flavor, create a VM, assign a floating IP, check the security group, log in with SSH, then stop, start and delete it.
sidebar:
  order: 3
---

Create a first VM on the all-in-one host from [Install](/en/quickstart/install/).
Horizon can do the same ([Horizon guide](/en/guides/horizon/)); this page uses the CLI, which is easy to reproduce.

Become root and load the admin credentials:

```bash
sudo -i
. /etc/hagistack/admin-openrc
```

Run the following commands in this root shell.

## 12. Check the image and the flavor

```bash
openstack image list
openstack flavor list
```

**Expected result (example):** the image `cirros-0.6.3-x86_64` is `active`, and the flavor `m1.tiny` (RAM 256, Disk 1, VCPUs 1) is listed.

<div class="example-output">

```text
+--------------------------------------+---------------------+--------+
| ID                                   | Name                | Status |
+--------------------------------------+---------------------+--------+
| 3f0c...                              | cirros-0.6.3-x86_64 | active |
+--------------------------------------+---------------------+--------+
```

</div>

:::note[About example output]
Example output on this site shows the format only. It is not captured from a real host; IDs and other values differ on every installation.
:::

## 13. Create a VM

```bash
openstack server create --flavor m1.tiny --image cirros-0.6.3-x86_64 \
    --network hagistack-tenant --key-name hagistack-key --wait demo1
```

- **What it does:** creates the VM `demo1` on the tenant network and injects the public key of `hagistack-key` through the metadata service. `--wait` waits until it is up.
- **Security group:** without `--security-group`, the project's `default` group is used. HAGISTACK has added SSH and ICMP rules to the admin project's `default` group.

## 14. Check that the VM is ACTIVE

```bash
openstack server list
openstack server show demo1 -c status -c addresses
```

**Expected result:** `status` is `ACTIVE`, and `addresses` shows `hagistack-tenant=10.10.10.x`.
If it is `ERROR`, see [Troubleshooting](/en/operations/troubleshooting/).

The boot log (including cloud-init's output):

```bash
openstack console log show demo1
```

## 15. Assign a floating IP

```bash
openstack floating ip create hagistack-provider
openstack server add floating ip demo1 FLOATING_IP
```

- Replace `FLOATING_IP` with the `floating_ip_address` printed by the first command (for example `198.51.100.150`).
- **Expected result:** `openstack server show demo1 -c addresses` shows both the tenant address and the floating IP.

:::caution[A floating IP is not reachable from the physical LAN as it is]
HAGISTACK does not attach the provider NIC to `br-ex`, so the floating IP cannot be reached from outside as it is.
On a single host, give the host's own `br-ex` the provider gateway address, as in method B below; **that host** can then reach the floating IPs (as the acceptance tests did).
Attaching a physical NIC to `br-ex` to reach them from a LAN is not verified.
:::

## 16. Check the security group

```bash
SG=$(openstack security group list --project admin -f value -c ID -c Name | awk '$2=="default"{print $1}')
openstack security group rule list "$SG"
```

Every project has a group named `default`, so a name alone is ambiguous. Look up the ID of the admin project's `default` group first (HAGISTACK adds its rules the same way).
**Expected result:** ingress rules for `tcp` `22:22` and for `icmp`.

## 17. Log in to the VM with SSH

The CirrOS user is `cirros`, and the key is `/etc/hagistack/hagistack-key`. There are two ways in.

### Method A: the tenant address, from the metadata namespace

The host that runs the VM (the same host on all-in-one) has an OVN metadata namespace for the tenant network. SSH to the VM's tenant address from there:

```bash
NETID=$(openstack network show hagistack-tenant -f value -c id)
ip netns exec ovnmeta-$NETID ssh -i /etc/hagistack/hagistack-key cirros@TENANT_IP
```

`TENANT_IP` is the `10.10.10.x` address from step 14. This is how the all-in-one acceptance test (s66r5c) logged in.

### Method B: the floating IP, from the host

Give the host's `br-ex` the provider gateway address; this host then reaches the floating IPs.
`198.51.100.1/24` is an example: use your `--provider-gateway` and the prefix of your `--provider-cidr`.

```bash
ip addr add 198.51.100.1/24 dev br-ex
ip link set br-ex up
ssh -i /etc/hagistack/hagistack-key cirros@FLOATING_IP
```

This is how the controller + compute acceptance test (s66r5d) logged in.
The `ip addr add` setting is lost at a reboot. It is not a production way to provide external access.

**Expected result:** you log in as `cirros` without a password and get a `$` prompt. In the VM, `curl http://169.254.169.254/latest/meta-data/instance-id` returns the instance ID from the metadata service.

## 18. Stop, start and delete the VM

```bash
openstack server stop demo1
openstack server show demo1 -c status      # SHUTOFF
openstack server start demo1
openstack server show demo1 -c status      # ACTIVE
openstack server delete --wait demo1
```

The floating IP stays after the VM is deleted. Release it when you no longer need it:

```bash
openstack floating ip list
openstack floating ip delete FLOATING_IP
```

:::danger[Deletion cannot be undone]
`server delete` and `floating ip delete` cannot be undone. Check the name and ID first.
:::

## Read next

- [Horizon guide](/en/guides/horizon/): the same tasks in the browser
- [Add a compute node](/en/guides/add-compute/): add a second host
- [OpenStack CLI guide](/en/cli/overview/): users, images and networks
