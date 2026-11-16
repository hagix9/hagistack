---
title: インストール前の準備
description: Rocky Linux 10.2 ホストの要件、管理ネットワークと provider ネットワーク、正式版の取得、設定ファイルの作成。
sidebar:
  order: 1
---

クイックスタートは 3 ページで構成されています。

1. **インストール前の準備**（このページ）：ホストの要件確認、HAGISTACK の取得、設定ファイルの作成
2. [インストール](/ja/quickstart/install/)：preflight、`all-in-one`、`status`、Horizon へのログイン
3. [最初の VM](/ja/quickstart/first-vm/)：VM の作成、Floating IP、SSH ログイン、停止・起動・削除

対象は、Linux の基本操作ができる OpenStack 初心者です。ここでは 1 台に全部を入れる **All-in-one** 構成を作ります。

## 1. Rocky Linux 10.2 を用意する

クリーンインストールした **Rocky Linux 10.2（x86_64）** を 1 台用意します。

- ほかの EL10 系（RHEL、AlmaLinux、CentOS 10）は警告付きで続行しますが、**検証していません**。それ以外の OS とアーキテクチャは拒否されます。
- `sudo` で root になれるユーザーで作業します。
- init は systemd が前提です。

## 2. CPU・メモリ・ディスク・NIC を確認する

| 項目 | 要件 | 補足 |
|---|---|---|
| メモリ | 8 GB 以上 | 約 7 GB 未満で preflight が警告します |
| ディスク | `/` に 20 GB 以上の空き | 検証時の All-in-one ノードは 60 GB |
| 仮想化支援 | `/dev/kvm` が読めること | ない場合は `qemu` のソフトウェアエミュレーションになり、10〜50 倍遅くなります |
| NIC | 管理用の NIC と、provider NIC として指定する実在のインターフェース | provider NIC はブリッジに**接続されません**（後述） |
| ホスト名 | ノードごとに異なる短いホスト名 | Nova のホスト名と OVN の chassis 名に使われます |
| 時刻同期 | chronyd などで同期 | |
| インターネット接続 | GitHub、EPEL 10、CentOS NFV SIG、RDO の依存リポジトリ、CirrOS | 下記参照 |

仮想化支援が使えるかは次で確認できます。

```bash
ls -l /dev/kvm
grep -cE 'vmx|svm' /proc/cpuinfo
```

`/dev/kvm` が存在し、2 行目が 1 以上なら KVM が使えます。
クラウド上の VM で試す場合は、ネスト仮想化を有効にする必要があります（例：GCE はネスト仮想化対応のマシンタイプとオプションが必要です）。

インストーラーは次のリポジトリを追加し、インターネットから取得します。

- `https://github.com/hagix9/hagistack/releases/download/`（HAGISTACK の RPM。約 108 MB）
- EPEL 10（CRB も有効にします）
- CentOS Stream 10 NFV SIG（Open vSwitch と OVN）
- RDO の EL10 向けサードパーティ依存リポジトリ（Python ライブラリ、RabbitMQ/Erlang）
- `download.cirros-cloud.net`（最初のゲストイメージ。`--image-file` を指定すれば不要）

:::caution[SELinux は permissive に切り替わります]
HAGISTACK は SELinux を permissive に切り替え、再起動後も維持されるよう `/etc/selinux/config` を書き換えます。
OpenStack 用の SELinux ポリシーは導入せず、enforcing は検証していません。
:::

## 3. 管理ネットワークと provider ネットワークを理解する

HAGISTACK が扱うネットワークは 3 種類です。

| ネットワーク | 役割 | 設定値 |
|---|---|---|
| **管理ネットワーク** | OpenStack の API、データベース、メッセージング、ノード間通信。Horizon もこのアドレスで開きます | 管理 IP（`--mgmt-ip`。既定は `8.8.8.8` への経路の送信元アドレス） |
| **provider ネットワーク** | 外部ネットワーク `hagistack-provider`。Floating IP はこの範囲から払い出されます | `--provider-cidr`、`--provider-gateway`、`--floating-start`、`--floating-end` |
| **テナントネットワーク** | VM が接続されるプライベートネットワーク `hagistack-tenant` | `--tenant-cidr`（既定 `10.10.10.0/24`） |

:::caution[provider NIC はブリッジに接続されません]
HAGISTACK は provider 用のブリッジ `br-ex` を作りますが、`--ext-nic` で指定した NIC を `br-ex` に**接続しません**。
そのため、自分で接続するまで provider ネットワークと Floating IP は物理 LAN に届きません。
物理 LAN からの到達は検証していません。
1 台で試す場合の VM へのログイン方法は [最初の VM](/ja/quickstart/first-vm/) で説明します。
:::

このガイドでは、例示用に次の値を使います。

| 項目 | 例 |
|---|---|
| 管理 IP | `192.0.2.10` |
| provider NIC | `eth1` |
| provider CIDR | `198.51.100.0/24` |
| provider ゲートウェイ | `198.51.100.1` |
| Floating IP の範囲 | `198.51.100.100` 〜 `198.51.100.200` |

:::danger[例示用アドレスをそのまま使わないでください]
`192.0.2.0/24` と `198.51.100.0/24` は RFC 5737 で定められた**文書用のアドレス**です。
実際のネットワークでは使えません。必ず自分の環境の値に置き換えてください。
NIC 名も環境によって異なります（`ip -br link` で確認できます）。
:::

## 4. GitHub の正式タグから HAGISTACK を取得する

正式版のタグ `rocky10.2-rpms-2026.1` を指定して取得します。

```bash
sudo dnf -y install git
git clone --branch rocky10.2-rpms-2026.1 https://github.com/hagix9/hagistack.git
cd hagistack/rocky10.2
```

このタグには `rpm-release.lock` が含まれています。インストーラーはこのファイルに固定された SHA-256、サイズ、RPM セットの同一性で、ダウンロードした RPM を検証します。
タグより古いチェックアウトにはリリースが固定されておらず、既定の取得方法（`github`）は停止します。

## 5. 設定ファイルを作成する

設定はコマンドラインか設定ファイルで渡します。両方ある場合はコマンドラインが優先されます。
設定ファイルは、`./hagistack.env`、スクリプトと同じ場所の `hagistack.env`、`/etc/hagistack/hagistack.env` の順に探されます。

`hagistack/rocky10.2/hagistack.env` を作ります（値は自分の環境に置き換えてください）。

```bash
cat > hagistack.env <<'EOF'
# RPM_SOURCE の既定は github（公開リリース）
EXT_NIC=eth1
PROVIDER_CIDR=198.51.100.0/24
PROVIDER_GATEWAY=198.51.100.1
FLOATING_START=198.51.100.100
FLOATING_END=198.51.100.200
EOF
```

- 書式は `KEY=VALUE` の行、空行、`#` コメントだけです。ファイルは解釈されるだけで、実行はされません。
- **パスワードを書かないでください。** パスワードは HAGISTACK が生成します。
- 環境変数は読みません。

主な設定項目：

| オプション | キー | 必須 | 既定値 |
|---|---|---|---|
| `--ext-nic NAME` | `EXT_NIC` | all-in-one、controller | — |
| `--provider-cidr CIDR` | `PROVIDER_CIDR` | all-in-one、controller | — |
| `--provider-gateway IP` | `PROVIDER_GATEWAY` | all-in-one、controller | — |
| `--floating-start IP` | `FLOATING_START` | all-in-one、controller | — |
| `--floating-end IP` | `FLOATING_END` | all-in-one、controller | — |
| `--mgmt-ip IP` | `MGMT_IP` | | 自動検出 |
| `--tenant-cidr CIDR` | `TENANT_CIDR` | | `10.10.10.0/24` |
| `--dns-server IP` | `DNS_SERVER` | | provider ゲートウェイ |
| `--virt-type kvm\|qemu` | `VIRT_TYPE` | | `/dev/kvm` から自動判定 |
| `--image-file PATH` | `IMAGE_FILE` | | — （ダウンロードせずにローカルのイメージを使う） |

すべての項目は `rocky10.2/README.ja.md` の「設定」にあります。

次は [インストール](/ja/quickstart/install/) です。
