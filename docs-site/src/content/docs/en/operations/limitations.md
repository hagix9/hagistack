---
title: Known limitations
description: What the release rocky10.2-rpms-2026.1 does not include, what is not verified, and what is not supported.
sidebar:
  order: 4
---

This page is about the release `rocky10.2-rpms-2026.1`.

## Not included

- **Provider NIC attachment:** the provider NIC is **never attached** to `br-ex`. Until you attach one, the provider network and floating IPs reach no physical LAN.
- **Other services:** Cinder (volumes), Swift and other services are not installed.
- **noVNC console:** the console proxy is not installed, so Horizon's console tab does not work. Support is in development ([noVNC console (in development)](/en/development/novnc/)).
- **SELinux policy:** no OpenStack SELinux policy is installed, and the host is switched to permissive.
- **Firewall:** no host firewall is configured automatically. The APIs, RabbitMQ, the OVN southbound database and memcached listen on the management network: keep the nodes on a trusted network.
- **Package signatures:** the RPMs are not GPG-signed, and the added repositories use `gpgcheck=0`. Integrity is checked against the SHA-256 and RPM-set identity pinned by the lock in the Git tag.

## Not verified

- SELinux enforcing
- the package test suites (`%check`)
- paths beyond the tenant network (a physical LAN, floating IPs reached from outside the host)
- live migration
- three or more nodes
- other EL10 distributions (RHEL, AlmaLinux, CentOS 10)
- hosts with an active firewall
- a full run of the `github` download from the GitHub Release on a real Rocky Linux 10.2 host (after publication, the download of the published assets, their SHA-256, the lock and the installer's download checks were verified offline)

## Not supported

- architectures other than x86_64
- switching the RPM set of a running cloud (upgrades)

## Acceptance tests and the published RPMs

| Test | RPMs used |
|---|---|
| All-in-one (2026-11-15, run s66r5c) | **the same bytes** as the published RPMs |
| Controller + compute (2026-11-16, run s66r5d) | a rebuild from the same sources and the same 195 package versions (different bytes) |
