---
title: Neutron（ネットワーク）
description: ネットワーク、サブネット、ルーター、Floating IP、セキュリティグループ、エージェントの確認と操作。
sidebar:
  order: 5
---

Neutron は仮想ネットワークを管理します。HAGISTACK は ML2/OVN を使います。

## 一覧

```bash
openstack network list
openstack subnet list
openstack router list
openstack floating ip list
openstack security group list
```

| コマンド | HAGISTACK の初期状態 | Horizon |
|---|---|---|
| `network list` | `hagistack-provider`（外部・共有）、`hagistack-tenant` | Project → Network → Networks |
| `subnet list` | `hagistack-provider-subnet`（Floating IP の範囲、DHCP なし）、`hagistack-tenant-subnet` | 同上 |
| `router list` | `hagistack-router` | Project → Network → Routers |
| `floating ip list` | （作成するまで空） | Project → Network → Floating IPs |
| `security group list` | プロジェクトごとの `default` | Project → Network → Security Groups |

## ルーターの確認

```bash
openstack router show hagistack-router
```

`external_gateway_info` に `hagistack-provider` が、インターフェースにテナントサブネットがあります。

## Floating IP

```bash
openstack floating ip create hagistack-provider
openstack server add floating ip demo1 FLOATING_IP
openstack server remove floating ip demo1 FLOATING_IP
openstack floating ip delete FLOATING_IP
```

:::caution
Floating IP が物理 LAN から届くかは、provider NIC の接続次第です。HAGISTACK は provider NIC を `br-ex` に接続しません（[最初の VM](/ja/quickstart/first-vm/#15-floating-ip-を割り当てる)）。
:::

## セキュリティグループ

```bash
SG=$(openstack security group list --project admin -f value -c ID -c Name | awk '$2=="default"{print $1}')
openstack security group rule list "$SG"
openstack security group rule create --protocol tcp --dst-port 80 --remote-ip 192.0.2.0/24 "$SG"
```

- `default` という名前はプロジェクトごとにあるため、ID で指定します。
- `--remote-ip` で送信元を限定してください（例のアドレスは RFC 5737 の文書用です）。
- 不要なルールは `openstack security group rule delete RULE_ID` で削除します。

## 新しいテナントネットワークを作る

```bash
openstack network create net2
openstack subnet create --network net2 --subnet-range 10.20.0.0/24 net2-subnet
openstack router add subnet hagistack-router net2-subnet
```

既存のルーターに接続すると、`net2` の VM も Floating IP を使えます。サブネットの範囲は既存のネットワークと重ならないようにしてください。

## エージェント

```bash
openstack network agent list
```

各ノードの `OVN Controller agent`（controller は `OVN Controller Gateway agent`）と `OVN Metadata agent` が `Alive` = `True` になります。

:::danger
`network delete`、`subnet delete`、`router delete` は取り消せません。`hagistack-*` の初期リソースを削除すると、HAGISTACK の再実行で作り直されますが、接続していた VM の通信は切れます。
:::
