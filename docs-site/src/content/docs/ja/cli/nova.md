---
title: Nova（VM）
description: VM の一覧・作成・起動・停止・再起動・削除、Compute サービスとハイパーバイザ、配置先の確認。
sidebar:
  order: 4
---

Nova は VM（インスタンス、CLI では `server`）を管理します。

## VM の一覧と詳細

```bash
openstack server list
openstack server list --all-projects --long     # 管理者：全プロジェクト
openstack server show demo1
```

| 項目 | 内容 |
|---|---|
| 期待される出力 | 名前、状態（`ACTIVE`、`SHUTOFF`、`ERROR` など）、ネットワークとアドレス、イメージ、Flavor |
| 必要な権限 | 自分のプロジェクトの VM は member。`--all-projects` は管理者 |
| Horizon | Project → Compute → Instances（管理者は Admin → Compute → Instances） |

## VM を作る

```bash
openstack server create --flavor m1.tiny --image cirros-0.6.3-x86_64 \
    --network hagistack-tenant --key-name hagistack-key --wait demo1
```

| オプション | 意味 |
|---|---|
| `--flavor` | CPU・メモリ・ディスクの大きさ |
| `--image` | 起動元のイメージ |
| `--network` | 接続するネットワーク（テナントネットワーク） |
| `--key-name` | 注入する SSH 公開鍵 |
| `--security-group` | セキュリティグループ（省略時は `default`） |
| `--wait` | `ACTIVE` になるまで待つ |

HAGISTACK は Cinder（ボリューム）を導入しないため、VM のディスクは Compute ノードのローカルディスクに作られます。

## 起動・停止・再起動・削除

```bash
openstack server stop demo1
openstack server start demo1
openstack server reboot demo1          # ソフトリブート
openstack server reboot --hard demo1   # ハードリブート
openstack server delete --wait demo1
```

:::danger
`server delete` は VM とそのローカルディスクを削除します。取り消せません。
:::

## 起動ログ

```bash
openstack console log show demo1
```

cloud-init の出力などを確認できます。Horizon ではインスタンスの **Log** タブです。

:::note[コンソール URL]
`openstack console url show --novnc demo1` は noVNC のコンソール URL を返すコマンドですが、正式版 `rocky10.2-rpms-2026.1` は noVNC プロキシを導入しないため使えません（[noVNC コンソール（開発中）](/ja/development/novnc/)）。
:::

## Compute サービスとハイパーバイザ

```bash
openstack compute service list
openstack hypervisor list
openstack hypervisor show HYPERVISOR_HOSTNAME
```

| コマンド | 期待される出力 | 権限 | Horizon |
|---|---|---|---|
| `compute service list` | `nova-scheduler`、`nova-conductor`、`nova-compute`（ホストごと）が `enabled` / `up` | 管理者 | Admin → System → System Information |
| `hypervisor list` | Compute ホストが `up` | 管理者 | Admin → Compute → Hypervisors |

## VM の配置先

```bash
openstack server show demo1 -c name -c status -c OS-EXT-SRV-ATTR:host
openstack server list --all-projects --host HOSTNAME
```

`OS-EXT-SRV-ATTR:host` は管理者だけが見られます。配置の仕組みと配置先の指定は [Compute ノードの追加](/ja/guides/add-compute/#8-vm-の配置について) を参照してください。

## Flavor

```bash
openstack flavor list
openstack flavor create --vcpus 1 --ram 512 --disk 2 m1.small
```

Flavor の作成・削除は管理者だけができます。`--ram` は MiB、`--disk` は GiB です。
