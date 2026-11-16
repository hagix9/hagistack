---
title: Horizon 操作ガイド
description: Horizon（OpenStack ダッシュボード）へのログインと、イメージ・Flavor・インスタンス・ネットワーク・Floating IP・セキュリティグループ・キーペアの操作。
sidebar:
  order: 1
---

Horizon は、ブラウザから OpenStack を操作するダッシュボードです。HAGISTACK では `Hagistack Dashboard` という名前で表示されます。

:::note[このページの検証範囲]
HAGISTACK の受入試験で実際に確認しているのは、admin でのサインイン、保護されたページの表示、ロゴと静的ファイルの読み込みです。
インスタンスの作成や Floating IP の割り当ては、受入試験では **CLI で** 確認しています。
このページの画面操作は Horizon 2026.1 の標準的なメニューに沿った説明で、画面ごとの検証はしていません。実際の画面のスクリーンショットはまだ掲載していません。
:::

:::caution[コンソール（noVNC）は現行の正式版では使えません]
正式版 `rocky10.2-rpms-2026.1` は noVNC コンソールプロキシを導入しないため、インスタンスの **コンソール** タブは使えません。
VM の起動ログは **ログ** タブ（`openstack console log show` と同じ内容）で確認できます。
noVNC 対応は開発中です（[noVNC コンソール（開発中）](/ja/development/novnc/)）。
:::

## ログイン

| 項目 | 値 |
|---|---|
| URL | `http://管理IP/dashboard/` |
| ドメイン | `Default`（入力欄は表示されません） |
| ユーザー名 | `admin` |
| パスワード | `/etc/hagistack/admin-openrc` の `OS_PASSWORD` |

ログイン画面の言語はブラウザの設定に従います。メニュー名は英語表示を基準に記載し、括弧内に日本語表示の目安を添えます（翻訳は Horizon の版によって異なることがあります）。

## プロジェクトの選択

画面左上のプロジェクト名をクリックすると、操作対象のプロジェクトを切り替えられます。HAGISTACK が作る初期リソース（テナントネットワーク、キーペア、セキュリティグループのルール）は **admin** プロジェクトにあります。

## イメージ

**Project → Compute → Images**（プロジェクト → コンピュート → イメージ）

- `cirros-0.6.3-x86_64` が公開イメージとして登録されています。
- **Create Image** で qcow2 などのイメージファイルをアップロードできます。

## Flavor

**Admin → Compute → Flavors**（管理 → コンピュート → フレーバー）

- `m1.tiny`（vCPU 1、RAM 256 MiB、ディスク 1 GiB）が作成されています。
- Flavor の作成と削除は管理者だけができます。

## キーペア

**Project → Compute → Key Pairs**（プロジェクト → コンピュート → キーペア）

- `hagistack-key` があります。秘密鍵はホストの `/etc/hagistack/hagistack-key` にあり、Horizon からはダウンロードできません。
- **Create Key Pair** で新しいキーペアを作ると、秘密鍵はその場で一度だけダウンロードされます。

## インスタンスの作成

**Project → Compute → Instances → Launch Instance**（インスタンスの起動）

ウィザードで次を指定します。

| タブ | 設定 |
|---|---|
| Details（詳細） | インスタンス名（例：`demo2`） |
| Source（ソース） | ブートソースに **Image** を選び、`cirros-0.6.3-x86_64` を割り当てる。HAGISTACK は Cinder（ボリューム）を導入しないため、ボリュームを作成する選択肢が表示される場合は **No（いいえ）** を選ぶ |
| Flavor（フレーバー） | `m1.tiny` |
| Networks（ネットワーク） | `hagistack-tenant`（`hagistack-provider` ではありません） |
| Security Groups（セキュリティグループ） | `default` |
| Key Pair（キーペア） | `hagistack-key` |

**Launch Instance** を押すと作成が始まります。**Status** が `Active`、**Power State** が `Running` になれば起動完了です。

## ネットワーク

**Project → Network → Networks / Routers / Network Topology**

- `hagistack-tenant`（テナント）と `hagistack-provider`（外部、共有）があります。
- **Network Topology** で、ルーター `hagistack-router` がテナントと provider をつないでいる様子を確認できます。

## Floating IP の割り当て

**Project → Network → Floating IPs → Allocate IP To Project**

1. Pool に `hagistack-provider` を選んで割り当てます。
2. 一覧の **Associate** から、インスタンスのポートを選んで関連付けます。

インスタンス一覧の **Associate Floating IP** からも同じ操作ができます。
Floating IP が物理 LAN から届くかどうかは環境次第です。詳しくは [最初の VM](/ja/quickstart/first-vm/#15-floating-ip-を割り当てる) を参照してください。

## セキュリティグループ

**Project → Network → Security Groups**

- admin プロジェクトの `default` に、SSH（TCP 22）と ICMP の ingress ルールが追加されています。
- **Manage Rules → Add Rule** でルールを追加できます。必要な通信だけを許可してください。

## VM の起動・停止・削除

インスタンス一覧の右端のメニューから操作します。

| 操作 | メニュー | CLI での対応 |
|---|---|---|
| 停止 | Shut Off Instance | `openstack server stop` |
| 起動 | Start Instance | `openstack server start` |
| 再起動 | Soft / Hard Reboot Instance | `openstack server reboot [--hard]` |
| 削除 | Delete Instance | `openstack server delete` |
| ログの表示 | インスタンス名 → Log | `openstack console log show` |

:::danger
削除は元に戻せません。
:::

## VM の状態確認

インスタンス名をクリックすると、**Overview**（概要）で状態、Flavor、IP アドレス、作成日時を確認できます。
管理者は **Admin → Compute → Instances** で、すべてのプロジェクトのインスタンスと、動いている Compute ホストを確認できます。
