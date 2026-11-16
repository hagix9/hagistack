---
title: CLI の基本
description: OpenStack CLI（openstack コマンド）の認証情報の読み込み、出力形式、ヘルプ、Horizon との対応。
sidebar:
  order: 1
---

HAGISTACK は controller に `openstack` コマンド（python-openstackclient）を導入します。
このガイドのコマンド構文は、ノードに導入される版と同じ **python-openstackclient 9.0.1**（openstacksdk 4.10.0）の `--help` で確認しています。

## 認証情報を読み込む

```bash
sudo -i
. /etc/hagistack/admin-openrc
```

- `/etc/hagistack/admin-openrc` は admin ユーザーの認証情報です（root だけが読めます）。
- 読み込むと、Keystone の URL（`http://管理IP:5000/v3`）、ユーザー `admin`、プロジェクト `admin` などが環境変数に設定されます。
- 動作確認：

```bash
openstack token issue -c expires -c project_id
openstack catalog list
```

`catalog list` には identity、image、placement、network、compute のサービスが表示されます。

:::caution[admin は強い権限を持ちます]
admin の認証情報では、すべてのプロジェクトのリソースを削除できます。日常的な利用者には、[Keystone](/ja/cli/keystone/) で権限を絞ったユーザーを作ることを勧めます。
:::

## ヘルプと出力形式

```bash
openstack help server create      # サブコマンドのヘルプ
openstack server list -f json      # JSON で出力
openstack server list -f value -c ID -c Name   # 値だけ、列を指定
```

| オプション | 意味 |
|---|---|
| `-f table` | 表形式（既定） |
| `-f json` / `-f yaml` | 機械可読な形式 |
| `-f value` | 値だけ（スクリプト向け） |
| `-c COLUMN` | 表示する列を指定（複数可） |

## 出力例の扱い

各ページの出力例は書式を示すための例で、実機から取得したログではありません（例である場合は「出力例」と明記しています）。ID、日時、ホスト名は環境ごとに異なります。

## 破壊的な操作

`delete`、`remove`、`set --disable` などは、リソースを削除・変更します。多くは取り消せません。
実行前に `list` / `show` で対象の名前と ID を確認してください。

## CLI と Horizon の対応

| CLI | Horizon |
|---|---|
| `openstack user list` | Identity → Users |
| `openstack project list` | Identity → Projects |
| `openstack image list` | Project → Compute → Images |
| `openstack flavor list` | Admin → Compute → Flavors |
| `openstack server list` | Project → Compute → Instances |
| `openstack keypair list` | Project → Compute → Key Pairs |
| `openstack network list` | Project → Network → Networks |
| `openstack router list` | Project → Network → Routers |
| `openstack floating ip list` | Project → Network → Floating IPs |
| `openstack security group list` | Project → Network → Security Groups |
| `openstack hypervisor list` | Admin → Compute → Hypervisors |
| `openstack compute service list` | Admin → System → System Information |

各サービスのページ：[Keystone](/ja/cli/keystone/)、[Glance](/ja/cli/glance/)、[Nova](/ja/cli/nova/)、[Neutron](/ja/cli/neutron/)、[Placement](/ja/cli/placement/)。
