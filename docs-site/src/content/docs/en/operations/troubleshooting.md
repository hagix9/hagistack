---
title: Troubleshooting
description: Common problems with the installation, Horizon, VMs and compute nodes, and how to check them.
sidebar:
  order: 3
---

## Installation

| Symptom | Cause and fix |
|---|---|
| `no published RPM release is pinned` | the checkout is older than the tag `rocky10.2-rpms-2026.1`. Clone the release tag, or use `--rpm-source build` or `--repo-url` |
| The download or a verification fails | nothing was installed. Check the network and re-run; it never switches to building |
| `Switching the package set of a running cloud is an upgrade` | the host was deployed from another RPM set. HAGISTACK does not upgrade |
| A warning that `delorean-component-*` repositories are enabled | disable them: `dnf config-manager --set-disabled 'delorean-component-*'`. Otherwise the install is no longer one release |
| It stops without an `error:` line | the last `==>` line of the output is the phase that failed |
| `INCOMPLETE — these phases were skipped` | fix the cause shown for those phases and re-run |

## Horizon cannot be reached

1. The URL is `http://MGMT_IP/dashboard/` (the trailing `/dashboard/` is needed).
2. Check httpd on the controller:

   ```bash
   systemctl status httpd
   curl -s -o /dev/null -w '%{http_code}\n' http://MGMT_IP/dashboard/auth/login/
   ```

   `200` means Horizon answers.
3. Check that the browser reaches port 80 of the management IP. With `firewalld` active, open 80/tcp (HAGISTACK configures no firewall).
4. The password is `OS_PASSWORD` in `/etc/hagistack/admin-openrc`.
5. `sudo ./tests-horizon-login.sh` checks the sign-in from the command line.

## A VM does not boot (ERROR)

```bash
openstack server show VM_NAME -c status -c fault
openstack compute service list
openstack hypervisor list
```

| `fault` | Fix |
|---|---|
| `No valid host was found` | no running compute service, or not enough free resources. Check that `nova-compute` is `up`. A controller alone cannot boot VMs until a compute node is added |
| `Refusing to bind port … no OVN chassis for host` | the Nova host name and the OVN chassis name disagree. Make every host name unique and stable, then re-run |

Logs on the compute node:

```bash
journalctl -u openstack-nova-compute -n 200
journalctl -u neutron-ovn-metadata-agent -n 100
```

## SSH does not connect

1. Is the VM `ACTIVE`?
2. Did cloud-init get the key? Check the boot log:

   ```bash
   openstack console log show VM_NAME | tail -40
   ```

3. Does the security group have an ingress rule for TCP 22 ([Your first VM](/en/quickstart/first-vm/#16-check-the-security-group))?
4. Check the path. A floating IP is not reachable from the physical LAN as it is: connect to the tenant address from the metadata namespace, or give the host's `br-ex` the gateway address ([Your first VM](/en/quickstart/first-vm/#17-log-in-to-the-vm-with-ssh)).
5. The user is `cirros`, the key `/etc/hagistack/hagistack-key`.

## Adding a compute node

See [the troubleshooting for adding a compute node](/en/guides/add-compute/#9-troubleshooting).

## Collecting information

When you report a problem, include no passwords or keys. Do not share `admin-openrc`, `secrets.env`, `compute-secrets.env` or `hagistack-key`.

```bash
sudo ./hagistack status
journalctl -u UNIT_NAME -n 200 --no-pager
```
