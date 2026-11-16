---
title: サービス状態の確認
description: HAGISTACK 独自の status（sudo ./hagistack status）、systemd、OpenStack CLI による状態確認と、再実行の考え方。
sidebar:
  order: 2
---

## HAGISTACK の状態確認（hagistack status）

`status` は HAGISTACK 独自のサブコマンドです。OpenStack 公式の CLI（`openstack` コマンド）とは別物で、HAGISTACK が導入したホストの状態を表示します。

`hagistack` スクリプトは PATH に登録されないため、取得したディレクトリ（`hagistack/rocky10.2`）で `./` を付けて実行します。root 権限が必要です。

```bash
cd hagistack/rocky10.2
sudo ./hagistack status
```

表示される内容：

- HAGISTACK の版と、対象のリリース・OS
- 役割（`all-in-one`、`controller`、`compute`）と RPM の取得方法・セット ID
- SELinux の現在の状態、起動時の設定、HAGISTACK が行った操作
- 完了したフェーズ
- 各サービスユニットの状態（`active` など）

:::note
`stage` と `unverified` の行は内容が古くなっています。
:::

## systemd で確認する

```bash
systemctl status openstack-nova-compute
journalctl -u openstack-nova-compute -n 100
```

主なユニット：

| ユニット | ノード |
|---|---|
| `mariadb`、`rabbitmq-server`、`memcached` | controller |
| `httpd`（Keystone、Placement、Neutron API、Nova API、Horizon） | controller |
| `openstack-glance-api` | controller |
| `ovn-northd` | controller |
| `neutron-rpc-server`、`neutron-periodic-workers`、`neutron-ovn-maintenance-worker` | controller |
| `openstack-nova-conductor`、`openstack-nova-scheduler` | controller |
| `ovn-controller`、`openvswitch` | 全ノード |
| `neutron-ovn-metadata-agent` | 全ノード |
| `openstack-nova-compute`、`libvirtd` | ハイパーバイザのあるノード |

## OpenStack CLI で確認する

```bash
sudo -i
. /etc/hagistack/admin-openrc
openstack compute service list
openstack hypervisor list
openstack network agent list
```

- `compute service list`：すべて `enabled` / `up`
- `hypervisor list`：各 Compute ホストが `up`
- `network agent list`：各エージェントが `Alive` = `True`

## 再実行

`all-in-one` と `compute-add` は再実行できるように作られています。

- **シークレット：** 既存のものを再利用し、ローテーションしません。
- **データベース：** 削除しません。
- **設定：** キー単位で編集し、設定が実行中のプロセスより新しいときだけサービスを再起動します。
- **初期リソース：** 名前で確認し、なければ作成します。

HAGISTACK はロールバックしません。失敗したら原因を直し、同じコマンドを再実行してください。
再実行は再構成のための道具ではありません。すでにあるリソースやエンドポイントはそのまま残ります。
