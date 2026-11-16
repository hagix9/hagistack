---
title: 構成とネットワーク
description: All-in-one と Controller + Compute の違い、各ノードで動くサービス、ネットワーク構成。
sidebar:
  order: 1
---

## All-in-one と Controller + Compute

| 構成 | コマンド | 内容 |
|---|---|---|
| All-in-one | `all-in-one` | 1 台にコントロールプレーンとハイパーバイザを入れる |
| Controller のみ | `controller` | ハイパーバイザなし。Compute ノードを追加するまで VM は起動できない |
| Controller にハイパーバイザを追加 | `compute-add --local` | Controller を All-in-one 相当にする（Controller の設定は変更しない） |
| Compute ノード | `compute-add --controller-ip IP` | 別ホストを Compute ノードとして追加する |

すでに導入済みのホストで実行できるコマンドは、記録された役割で決まります。

| 記録された役割 | `all-in-one` | `controller` | `compute-add --local` | リモートの `compute-add` |
|---|---|---|---|---|
| controller | 可（ハイパーバイザを追加） | 可（再実行） | 可 | 拒否 |
| all-in-one | 可（再実行） | 拒否 | 可（再実行） | 拒否 |
| compute | 拒否 | 拒否 | 拒否 | 可（再実行） |

役割は `/etc/hagistack/deployment.env` に記録されます。HAGISTACK がサービスを削除することはありません。

## 各ノードで動くサービス

| コンポーネント | Controller / All-in-one | Compute ノード |
|---|---|---|
| Keystone | httpd（mod_wsgi）、ポート 5000 | — |
| Glance | 独自ユニット、ポート 9292 | — |
| Placement | httpd、ポート 8778 | — |
| Nova | API（8774）と metadata API（8775）は httpd。conductor、scheduler | nova-compute、libvirt |
| Neutron | API（9696）は httpd。RPC サーバー、定期ワーカー、OVN メンテナンスワーカー | OVN metadata エージェント |
| OVN / Open vSwitch | northbound・southbound DB、ovn-northd、ovn-controller（ゲートウェイ chassis） | ovn-controller |
| Horizon | httpd、ポート 80 の `/dashboard` | — |
| MariaDB | `127.0.0.1` だけで待ち受け | — |
| RabbitMQ、memcached | 管理ネットワーク | — |

Compute ノードは**データベースに接続しません**（`nova.conf` のデータベース接続設定はコメントアウトされます）。admin の資格情報と provider のブリッジマッピングも持ちません。

## ネットワーク構成

```text
                 物理ネットワーク
  ─────────────┬──────────────────────┬─────────────  管理ネットワーク
               │ 管理 IP               │ 管理 IP
       ┌───────┴────────┐     ┌───────┴────────┐
       │ Node 1         │     │ Node 2         │
       │ controller     │     │ compute        │
       │  br-ex ── (provider NIC は接続されない)│
       │  OVN gateway   │     │                │
       │  VM            │     │  VM            │
       └────────────────┘     └────────────────┘
          ╲___________ Geneve トンネル（UDP 6081）___________╱
```

- **管理ネットワーク：** API、RabbitMQ、OVN southbound、memcached、ノード間の Geneve トンネル。
- **テナントネットワーク（`hagistack-tenant`）：** VM 同士の仮想ネットワーク。ノードをまたぐ通信は Geneve トンネルで運ばれます。
- **provider ネットワーク（`hagistack-provider`）：** `physnet1` → `br-ex` にマッピングされる flat ネットワーク。ルーター `hagistack-router` の外部ゲートウェイと Floating IP に使います。controller がゲートウェイ chassis です。
- **provider NIC：** HAGISTACK は `br-ex` に NIC を接続しません。物理 LAN と provider ネットワークをつなぐ場合は自分で設定する必要があり、その構成は検証していません。
- **MTU：** テナントネットワークの MTU は controller の管理インターフェースの MTU から決まります（`global_physnet_mtu`）。すべてのノードの管理インターフェースの MTU を揃えてください。

## RPM の取得と検証

```text
 --rpm-source github ─┐
 --rpm-source build  ─┼─▶ /var/lib/hagistack の検証済み RPM セット ─▶ file:// リポジトリ（priority=1）
 --rpm-source bundle ─┤
 --repo-url URL      ─┘─────────────────────────────────────────▶ 自前のリポジトリ
```

- **github（既定）：** GitHub Releases の asset をダウンロードし、Git タグ内の `rpm-release.lock` に固定された SHA-256・サイズ・RPM セット ID、`RPM-SHA256SUMS`、リポジトリのメタデータ、`rpm -K` で検証します。
- **build：** このホストのコンテナで RPM をソースからビルドします（数時間）。
- **bundle：** controller の RPM セットを Compute ノードで再利用します。
- **repo-url：** 自前のリポジトリを使います。HAGISTACK は検証しません。

失敗しても別の方法に自動で切り替えることはありません。1 つのクラウドでは 1 つの RPM セットだけを使います。
