---
title: Glance (images)
description: Listing, inspecting, registering and deleting OS images.
sidebar:
  order: 3
---

Glance stores the OS images VMs boot from. HAGISTACK registers `cirros-0.6.3-x86_64` as a public image.

## List and inspect

```bash
openstack image list
openstack image show cirros-0.6.3-x86_64
```

| Item | Value |
|---|---|
| What it does | reads the registered images |
| Expected output | `cirros-0.6.3-x86_64` is `active`; `show` gives `disk_format` `qcow2`, `visibility` `public`, and the property `hagistack_sha256` with the digest checked before upload |
| Permission | every user can read public images |
| Horizon | Project → Compute → Images |

## Register an image

A qcow2 image file:

```bash
openstack image create --disk-format qcow2 --container-format bare \
    --file ./my-image.qcow2 my-image
```

- `--public` makes it usable from every project (administrators only). Without it, only the current project can use it.
- Check the image against the checksum its publisher gives before you register it (for example `sha256sum my-image.qcow2`).
- Mind the disk space: images are stored on the controller's disk.

## Delete

```bash
openstack image delete my-image
```

:::danger
Deletion cannot be undone. If `cirros-0.6.3-x86_64` is deleted, a HAGISTACK re-run downloads and registers it again.
:::
