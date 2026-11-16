---
title: Keystone (identity)
description: Listing, creating, assigning and deleting users, projects and roles.
sidebar:
  order: 2
---

Keystone is OpenStack's identity service. A **user** holds a **role** on a **project**; that decides what the user may do.
HAGISTACK uses the `Default` domain only.

Load the admin credentials as in [CLI basics](/en/cli/overview/) first.

## Lists

```bash
openstack user list
openstack project list
openstack role list
```

| Command | Shows | Permission | Horizon |
|---|---|---|---|
| `openstack user list` | users (`admin`, and the service users `glance`, `nova`, `neutron`, `placement`, ...) | admin | Identity → Users |
| `openstack project list` | projects (`admin`, `service`) | admin | Identity → Projects |
| `openstack role list` | roles (`admin`, `member`, `reader`, ...) | admin | Identity → Roles |

:::caution[Leave the service users and project alone]
The `service` project and the users `glance`, `nova`, `neutron`, `placement` and so on are used by the OpenStack services. Changing their passwords or deleting them breaks the services.
:::

## Create a project and a user

As an example, create the project `demo` and the user `alice` as a member of it:

```bash
openstack project create --domain Default --description "Demo project" demo
openstack user create --domain Default --project demo --password-prompt alice
openstack role add --project demo --user alice member
```

- `--password-prompt` asks for the password. A password on the command line stays in the shell history and the process list.
- `role add` gives `alice` the `member` role on the `demo` project.

Check:

```bash
openstack role assignment list --user alice --names
```

**Expected result:** `member` assigned to `alice@Default` on `demo@Default`.

Horizon: Identity → Projects / Users.

## Work as the new user

For a credentials file for `alice`, copy `admin-openrc` and change `OS_USERNAME`, `OS_PROJECT_NAME` and `OS_PASSWORD`; `chmod 600` any file that holds a password.
To create VMs as `alice`, the `demo` project needs its own tenant network, key pair and security group rules (HAGISTACK's initial resources are in the admin project).

## Change and delete

```bash
openstack user set --password-prompt alice        # change the password
openstack role remove --project demo --user alice member
openstack user delete alice
openstack project delete demo
```

:::danger
`user delete` and `project delete` cannot be undone. Deleting a project does not delete its VMs or networks; delete them first.
:::
