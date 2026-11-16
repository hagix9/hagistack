---
title: インストール
description: preflight、All-in-one のインストール、status によるサービス確認、Horizon へのログイン。
sidebar:
  order: 2
---

[インストール前の準備](/ja/quickstart/prepare/) が終わっている前提で進めます。
コマンドはすべて `hagistack/rocky10.2` ディレクトリで実行します。

## 6. preflight を実行する

```bash
sudo ./hagistack all-in-one --check
```

- **意味：** 設定値と環境を検査し、解決した設定とその出所（コマンドライン、設定ファイル、自動検出）を表示します。**何も変更しません。**
- **検査する内容：** OS とアーキテクチャ、管理 IP、provider NIC の存在、provider アドレス（ゲートウェイと Floating IP の範囲が CIDR に含まれるか）、テナント CIDR、DNS、リージョン、`virt_type`、RPM の取得方法、ディスクとメモリ。
- **期待される結果：** エラーなく終了し、設定の一覧が表示されます。
- **検査しない内容：** RPM をダウンロードできるか（インストール中の RPM 取得フェーズで確認されます）。

設定ファイルを使わない場合は、オプションで渡します。

```bash
sudo ./hagistack all-in-one --check \
    --ext-nic eth1 --provider-cidr 198.51.100.0/24 --provider-gateway 198.51.100.1 \
    --floating-start 198.51.100.100 --floating-end 198.51.100.200
```

## 7. All-in-one でインストールする

```bash
sudo ./hagistack all-in-one
```

- **意味：** 正式版の RPM を GitHub Releases から取得・検証し、OpenStack 2026.1 一式を導入します。
- **所要時間：** 検証時の All-in-one ノード（n2-standard-8）で約 8 分でした。これに RPM（約 108 MB）のダウンロード時間が加わります。
- **期待される結果：** 最後に `every phase completed` と表示され、認証情報の場所、ダッシュボードの URL、Compute ノード追加のコマンドが表示されます。

フェーズは次の順に実行されます。

1. preflight
2. RPM の取得（ダウンロード、SHA-256・サイズ・RPM セット同一性・`rpm -K` の検証）
3. リポジトリ
4. SELinux
5. シークレット（パスワードの生成）
6. パッケージ
7. MariaDB → RabbitMQ → memcached
8. Keystone → Glance → Placement → OVS/OVN → Neutron → Nova → nova-compute
9. 初期リソース
10. Horizon

:::tip[失敗したときは]
HAGISTACK はロールバックしません。原因を直して同じコマンドを再実行してください。再実行は安全です。
既存のシークレットは再利用され、データベースは削除されず、設定は変更があるときだけ書き換えられます。
最後の `==>` の行が、失敗したフェーズです。
:::

### 作成される初期リソース

各リソースは名前で確認し、存在しなければ作成します。

| リソース | 内容 |
|---|---|
| Flavor | `m1.tiny`：vCPU 1、RAM 256 MiB、ディスク 1 GiB |
| イメージ | `cirros-0.6.3-x86_64`。アップロード前に SHA-256 で検証し、公開イメージとして登録 |
| 外部ネットワーク | `hagistack-provider`：flat、external、`physnet1`。サブネット `hagistack-provider-subnet` は Floating IP の範囲を持ち、DHCP なし |
| テナントネットワーク | `hagistack-tenant`、サブネット `hagistack-tenant-subnet` |
| ルーター | `hagistack-router`：provider ネットワークへのゲートウェイと、テナントサブネットのインターフェース |
| セキュリティグループ | admin プロジェクトの `default` に SSH（TCP 22）と ICMP を許可するルールを追加 |
| キーペア | `hagistack-key`。秘密鍵は `/etc/hagistack/hagistack-key`（モード `0600`） |

## 8. status でサービス状態を確認する

```bash
sudo ./hagistack status
```

- **意味：** 完了したフェーズ、SELinux の状態、各サービスユニットの状態を表示します。
- **期待される結果：** `services` の各行が `active` です（MariaDB、RabbitMQ、memcached、httpd、Glance、OVN、Open vSwitch、Neutron の各ワーカー、Nova の conductor・scheduler・compute、libvirtd）。

:::note
`status` の `stage` と `unverified` の行は内容が古くなっています。サービスの状態を確認する目的で使ってください。
:::

## 9. Horizon の URL を確認する

Horizon（ダッシュボード）は管理 IP の 80 番ポートで動いています。

```text
http://管理IP/dashboard/
```

例：`http://192.0.2.10/dashboard/`（例示用アドレスです）。
インストールの最後の表示にも `Dashboard :` として出ます。

:::caution
Horizon は HTTP で、`ALLOWED_HOSTS` は `['*']` です。HAGISTACK はファイアウォールを設定しないため、管理ネットワークは信頼できるネットワークに置いてください。
:::

## 10. admin ユーザーとパスワードを確認する

- **ユーザー：** `admin`
- **パスワード：** `/etc/hagistack/admin-openrc` の `OS_PASSWORD`

```bash
sudo grep '^export OS_PASSWORD=' /etc/hagistack/admin-openrc
```

:::danger[パスワードを公開しないでください]
このファイルは root だけが読めます（モード `0600`）。
パスワードを画面共有、スクリーンショット、ログ、チャットに出さないでください。
:::

## 11. Horizon にログインする

1. ブラウザで `http://管理IP/dashboard/` を開きます。
2. ユーザー名に `admin`、パスワードに上で確認した値を入力して **サインイン** します。
3. 左上のプロジェクトが `admin` になっていることを確認します。

ログインできない場合は [トラブルシューティング](/ja/operations/troubleshooting/) を参照してください。
コマンドラインからログインを確認する場合は、同梱の `tests-horizon-login.sh` を使えます。

```bash
sudo ./tests-horizon-login.sh
```

終了コード `0` が PASS です。

次は [最初の VM](/ja/quickstart/first-vm/) です。
