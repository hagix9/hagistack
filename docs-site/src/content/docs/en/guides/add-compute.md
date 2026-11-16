---
title: Add a compute node
description: Add a second Rocky Linux 10.2 host to an all-in-one as a compute node, map it into the Nova cell, and see where VMs run.
sidebar:
  order: 2
---

After building one all-in-one host with the [quick start](/en/quickstart/prepare/), add a second Rocky Linux 10.2 host as a compute node.

```text
Node 1: all-in-one (controller)
  Keystone / Glance / Placement / Nova API
  Neutron (OVN) / Horizon
  Nova Compute / VM

           management network (e.g. 192.0.2.0/24)

Node 2: compute
  Nova Compute / libvirt / VM
  OVN Controller / OVN Metadata Agent
```

:::note[What is verified]
- **Acceptance with RPMs rebuilt from the release's sources (2026-11-16, run s66r5d):** a controller without a hypervisor plus one compute node: registration, guests, SSH, metadata, traffic between nodes, a compute reboot and re-registration, and a `compute-add` re-run that changed nothing. This run used a rebuild from the same sources and the same 195 package versions as the release; its bytes differ from the published RPMs.
- **All-in-one plus a compute node:** verified on GCE on 2026-09-29 with an earlier RPM set.
- **Three or more nodes are not verified.**
:::

## 1. Prepare the second host

| Item | Requirement |
|---|---|
| OS | Rocky Linux 10.2 (x86_64) |
| Host name | a short host name **different from the controller's**. It is the Nova host name and the OVN chassis name; if they disagree, ports cannot bind |
| Virtualisation | `/dev/kvm` (otherwise qemu emulation) |
| MTU | the same management-interface MTU as the controller; a smaller one drops full-size packets in the tunnel |
| Clock | synchronised (chronyd or similar) |
| RPM set | **the same RPM set** as the controller; `compute-add` checks and stops otherwise |

The second host must reach these TCP ports on the controller's management IP:

| Port | Service |
|---|---|
| 5000 | Keystone |
| 9292 | Glance |
| 8778 | Placement |
| 9696 | Neutron API |
| 8775 | Nova metadata |
| 5672 | RabbitMQ |
| 6642 | OVN southbound |
| 11211 | memcached |

Geneve tunnels between the nodes use **UDP 6081** in both directions (not checked in advance).

HAGISTACK configures no firewall. If `firewalld` is active (on some clouds' Rocky Linux images it is), open the ports yourself:

```bash
# on the controller
sudo firewall-cmd --permanent --add-port={5000,9292,8778,9696,8775,5672,6642,11211}/tcp --add-port=6081/udp
# on the compute node
sudo firewall-cmd --permanent --add-port=6081/udp
# on both
sudo firewall-cmd --reload
```

Limit the sources to the management network.

:::tip[GCE and on-premises]
- **GCE:** the instances need nested virtualisation. Allow the ports above and UDP 6081 between the nodes in the VPC firewall rules. The acceptance tests used two nodes without external IPs in a VPC created for the run.
- **On-premises:** enable hardware virtualisation (VT-x / AMD-V) in the BIOS/UEFI, and let the ports above and UDP 6081 through switches and firewalls between the nodes.
:::

Clone the same release tag on the second host:

```bash
sudo dnf -y install git
git clone --branch rocky10.2-rpms-2026.1 https://github.com/hagix9/hagistack.git
```

## 2. Write the credentials on the controller

In `hagistack/rocky10.2` on the controller (node 1):

```bash
(umask 077; sudo ./hagistack compute-secrets > compute-secrets.env)
```

- **Content:** the five credentials a compute node needs (`RABBIT_PASS`, `NOVA_SERVICE_PASS`, `PLACEMENT_SERVICE_PASS`, `NEUTRON_SERVICE_PASS`, `METADATA_PROXY_SECRET`) and the controller's RPM-set identity (`RPM_SET_SHA256`, not a secret). No database password, no admin password.
- **Permissions:** your shell, not `hagistack`, creates the file; `umask 077` makes it readable by you only. `compute-secrets` refuses to write to a terminal.

:::danger[Handling the credentials]
The file is secret. Do not send it by e-mail or chat; copy it over an encrypted channel such as `scp`, and delete the controller's copy afterwards.
:::

## 3. Install the credentials on the compute node

```bash
# on the controller: copy, then delete
scp compute-secrets.env NODE2:/tmp/
shred -u compute-secrets.env
```

```bash
# on the compute node (node 2)
sudo install -d -m 0700 /etc/hagistack
sudo install -o root -g root -m 0600 /tmp/compute-secrets.env /etc/hagistack/secrets.env
shred -u /tmp/compute-secrets.env
```

`/etc/hagistack/secrets.env` is root:root, mode `0600`.

## 4. Add the compute node

In `hagistack/rocky10.2` on the compute node:

```bash
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP
```

`CONTROLLER_MGMT_IP` is the controller's management IP (for example `192.0.2.10`).

| How the controller got its RPMs | Command on the compute node |
|---|---|
| the published release (`github`, default) | `sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP` |
| built from source (`build`) | on the controller `sudo ./hagistack rpm-bundle --output /root/hagistack-rpms.tar`, copy it to the node, then `sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP --rpm-source bundle --rpm-bundle /root/hagistack-rpms.tar` |
| your own repository (`--repo-url`) | `sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP --repo-url URL` |

What `compute-add` does:

- It stops if `/etc/hagistack/secrets.env` is missing or has no valid `RPM_SET_SHA256`. It never generates secrets.
- It checks that the controller's ports are reachable **before** it changes anything.
- It stops before installing packages if this node's RPM set is not the controller's (the RPM-set check).
- The node gets no database connection, no admin credential and no provider bridge mapping.

## 5. Map the host into the Nova cell

On the controller:

```bash
sudo ./hagistack discover-hosts
```

This maps the new compute host into the Nova cell. The controller also does it every 300 seconds; run the command to use the node at once.

## 6. Check both compute services

On the controller:

```bash
sudo -i
. /etc/hagistack/admin-openrc
openstack compute service list --service nova-compute
openstack hypervisor list
```

**Expected result:** two `nova-compute` lines (node 1 and node 2), both `State` `up` and `Status` `enabled`; `hypervisor list` shows both hosts `up`.

The network side:

```bash
openstack network agent list
```

Node 2's `OVN Controller agent` and `OVN Metadata agent` show `Alive` = `True`.

## 7. See which node runs a VM

```bash
openstack server list
openstack server show demo1 -c name -c status -c OS-EXT-SRV-ATTR:host
```

`OS-EXT-SRV-ATTR:host` is the compute host the VM runs on.
With the default policy only **administrators** can see this field.

Per host:

```bash
openstack server list --all-projects --host NODE2_HOSTNAME
```

## 8. How VMs are placed

The **Nova scheduler** chooses the host:

1. **Filters** drop hosts that do not meet the conditions (free RAM, disk, vCPU, service up, ...).
2. **Weighers** score the remaining hosts; the highest score wins.

So two compute nodes do not mean VMs alternate or spread evenly.
HAGISTACK leaves the scheduler at its defaults.

Administrators can request a host at creation time (OpenStack 2026.1 CLI syntax):

```bash
# availability zone and host
openstack server create --flavor m1.tiny --image cirros-0.6.3-x86_64 \
    --network hagistack-tenant --key-name hagistack-key \
    --availability-zone nova:NODE2_HOSTNAME demo2

# compute API 2.74 or later: a requested host
openstack --os-compute-api-version 2.74 server create --flavor m1.tiny \
    --image cirros-0.6.3-x86_64 --network hagistack-tenant \
    --key-name hagistack-key --host NODE2_HOSTNAME demo3
```

:::caution[Not verified]
Both are syntax of the OpenStack 2026.1 CLI (python-openstackclient 9.0.1) and are **administrator-only**. The HAGISTACK acceptance tests did not run them.
Moving an existing VM to another host — **migration** and **live migration** — is a different feature. It is not verified on HAGISTACK and is not offered as a feature.
:::

## 9. Troubleshooting

| Symptom | What to check |
|---|---|
| The compute node is not registered | run `sudo ./hagistack discover-hosts` on the controller; `sudo ./hagistack status` on node 2 |
| `nova-compute` is `down` | `sudo journalctl -u openstack-nova-compute -n 100` on node 2; RabbitMQ (5672) reachable? clocks synchronised? |
| Not in `hypervisor list` | is it `up` in `openstack compute service list --service nova-compute`? was `discover-hosts` run? |
| A VM goes to `ERROR` | `openstack server show VM -c fault`. `Refusing to bind port … no OVN chassis for host` means the host name and the chassis name disagree: make every host name unique and stable, then re-run |
| No VM lands on node 2 | is node 2's `nova-compute` `up`, with enough free resources? The scheduler does not necessarily spread |
| The RPM sets differ | same source and same tag as the controller? `compute-secrets` regenerated with the controller's current version? |
| `compute-add` stops with "the controller is not reachable on every port" | nothing was installed; check the listed ports on the controller and any firewall in between |

See also [Troubleshooting](/en/operations/troubleshooting/).
