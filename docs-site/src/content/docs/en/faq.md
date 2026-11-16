---
title: FAQ
description: Questions about requirements, GCE and on-premises, Horizon, VMs, SSH and noVNC.
---

## What do I need to install?

A Rocky Linux 10.2 (x86_64) host, `sudo`, 8 GB of memory or more, 20 GB free on `/`, an existing interface to name as the provider NIC, the provider network values (CIDR, gateway, floating range) and internet access. See [Before you install](/en/quickstart/prepare/).

## Do I have to build the OpenStack RPMs?

No. With the release, the installer downloads the prebuilt RPMs from GitHub Releases and verifies them. Use `--rpm-source build` only if you want to build from source (it takes hours).

## What differs between GCE and on-premises?

- **GCE:** VMs run inside a VM, so the instance needs nested virtualisation. Allow the traffic between nodes in the VPC firewall rules. HAGISTACK's acceptance tests ran on GCE (asia-northeast1, nested KVM).
- **On-premises:** enable hardware virtualisation in the BIOS/UEFI and let the required ports through the firewalls and switches between nodes. Reaching floating IPs from a physical LAN needs the provider NIC attached to `br-ex` by you; that setup is not verified.

## I cannot reach Horizon

The URL is `http://MGMT_IP/dashboard/`. Check that httpd runs and that the browser reaches port 80 of the management IP (`firewalld` and the like). See [Troubleshooting](/en/operations/troubleshooting/#horizon-cannot-be-reached).

## My VM does not boot

`openstack server show VM_NAME -c fault` shows the error. For `No valid host was found`, check that `nova-compute` is `up` and that there are enough free resources. See [Troubleshooting](/en/operations/troubleshooting/#a-vm-does-not-boot-error).

## I cannot SSH to my VM

A floating IP is not reachable from the physical LAN as it is. Connect to the tenant address from the metadata namespace, or give the host's `br-ex` the provider gateway address ([Your first VM](/en/quickstart/first-vm/#17-log-in-to-the-vm-with-ssh)). The user is `cirros`, the key `/etc/hagistack/hagistack-key`.

## Can I use the noVNC console?

**Not with the release `rocky10.2-rpms-2026.1`.** Horizon's console tab does not work.
noVNC support is in development for the next release and has not been accepted on a real deployment yet ([noVNC console (in development)](/en/development/novnc/)).

## How many compute nodes can I add?

`compute-add` can be repeated, but only one added compute node (two nodes in all) is verified. Three or more nodes are not verified.

## Can SELinux be enforcing?

Not verified. HAGISTACK switches SELinux to permissive and installs no OpenStack SELinux policy (`openstack-selinux`).
