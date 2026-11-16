---
title: noVNC console (in development)
description: The state of noVNC console support in Horizon. Not part of the release rocky10.2-rpms-2026.1.
---

:::caution[In development]
The noVNC console is **not part of** the release `rocky10.2-rpms-2026.1`.
It is being developed for the next Rocky Linux 10.2 release and **has not been accepted on a real deployment (operating it from a browser) yet.**
This page may change.
:::

## In the current release

The release enables Nova's VNC server settings but installs neither the console proxy (`openstack-nova-novncproxy`) nor the browser client (`novnc`). Horizon's **Console** tab therefore does not work. Use the **Log** tab (`openstack console log show`) for the VM's state.

## The configuration in development

| Item | Value |
|---|---|
| Controller | installs `openstack-nova-novncproxy` (in HAGISTACK's RPM set) and `novnc` (from RDO's dependency repository); the proxy listens on TCP 6080 of the management address only |
| Every node | `nova.conf` `[vnc] novncproxy_base_url` points at the controller's proxy (`http://CONTROLLER_MGMT_IP:6080/vnc_lite.html`) |
| Connections | browser → the controller's 6080/tcp; proxy → the VNC port (5900/tcp and up) of the compute node that runs the guest |
| RPM set | unchanged (no new RPMs; an installer change only) |

## Security notes (configuration in development)

- The proxy is plain HTTP. Do not expose port 6080 to the internet; use it over the management network or a VPN. HTTPS/WSS is not configured.
- A console URL carries a one-time token that expires after 10 minutes by default. Do not share it.
- HAGISTACK configures no firewall. With `firewalld`, open the controller's 6080/tcp to the browsers that need it, and the compute nodes' 5900–5999/tcp to the controller only.
- SELinux is permissive, as for the other services.

## Status

| Item | Status |
|---|---|
| Installer change | implemented on a development branch |
| Local automated tests | done (package sets, `nova.conf` settings, listen address, no change on a re-run, proxy readiness probe) |
| Acceptance on a real all-in-one | **not done** |
| Acceptance on a real controller + compute | **not done** |
| Operating the console from a browser | **not done** |

Until it is accepted on a real deployment, this is not a released feature.
