---
title: Keystone（認証）
description: ユーザー、プロジェクト、ロールの一覧・作成・割り当て・削除。
sidebar:
  order: 2
---

Keystone は OpenStack の認証サービスです。**ユーザー**が**プロジェクト**に対して**ロール**を持つことで、権限が決まります。
HAGISTACK はドメイン `Default` だけを使います。

[CLI の基本](/ja/cli/overview/) の手順で admin の認証情報を読み込んでから実行してください。

## 一覧を見る

```bash
openstack user list
openstack project list
openstack role list
```

| コマンド | 何を見るか | 必要な権限 | Horizon |
|---|---|---|---|
| `openstack user list` | ユーザー（`admin` と、各サービスのユーザー `glance`、`nova`、`neutron`、`placement` など） | admin | Identity → Users |
| `openstack project list` | プロジェクト（`admin`、`service`） | admin | Identity → Projects |
| `openstack role list` | ロール（`admin`、`member`、`reader` など） | admin | Identity → Roles |

:::caution[サービス用のユーザーとプロジェクトを変更しないでください]
`service` プロジェクトと、`glance`・`nova`・`neutron`・`placement` などのユーザーは、OpenStack の各サービスが使っています。パスワードの変更や削除をすると、サービスが動かなくなります。
:::

## プロジェクトとユーザーを作る

例として、プロジェクト `demo` と、そのメンバーのユーザー `alice` を作ります。

```bash
openstack project create --domain Default --description "Demo project" demo
openstack user create --domain Default --project demo --password-prompt alice
openstack role add --project demo --user alice member
```

- `--password-prompt` はパスワードを対話的に入力します。コマンドラインにパスワードを書くと、シェルの履歴やプロセス一覧に残るため避けてください。
- `role add` で、`alice` に `demo` プロジェクトの `member` ロールを与えます。

確認：

```bash
openstack role assignment list --user alice --names
```

**期待される結果：** `member` ロールが `alice@Default` に `demo@Default` で割り当てられています。

Horizon では Identity → Projects / Users で同じ操作ができます。

## 新しいユーザーで操作する

`alice` 用の認証情報ファイルを作るときは、`admin-openrc` を参考に `OS_USERNAME`、`OS_PROJECT_NAME`、`OS_PASSWORD` を置き換えます。
パスワードを含むファイルは `chmod 600` にしてください。
`alice` で VM を作る場合、テナントネットワーク・キーペア・セキュリティグループは `demo` プロジェクトに別途用意する必要があります（HAGISTACK の初期リソースは admin プロジェクトにあります）。

## 変更と削除

```bash
openstack user set --password-prompt alice        # パスワードの変更
openstack role remove --project demo --user alice member
openstack user delete alice
openstack project delete demo
```

:::danger
`user delete` と `project delete` は取り消せません。プロジェクトを削除しても、その中の VM やネットワークは自動では消えません。先に中のリソースを削除してください。
:::
