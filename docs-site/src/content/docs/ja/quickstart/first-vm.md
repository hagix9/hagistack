---
title: 最初の VM
description: イメージと Flavor の確認、VM の作成、Floating IP、セキュリティグループ、SSH ログイン、停止・起動・削除。
sidebar:
  order: 3
---

[インストール](/ja/quickstart/install/) が終わった All-in-one ホストで、最初の VM を作ります。
同じ操作は Horizon でもできます（[Horizon 操作ガイド](/ja/guides/horizon/)）。ここでは確実に再現できる CLI で説明します。

まず root になり、管理者の認証情報を読み込みます。

```bash
sudo -i
. /etc/hagistack/admin-openrc
```

以降のコマンドは、この root シェルで実行します。

## 12. イメージと Flavor を確認する

```bash
openstack image list
openstack flavor list
```

**期待される結果（例）：** イメージ `cirros-0.6.3-x86_64` が `active`、Flavor `m1.tiny`（RAM 256、Disk 1、VCPUs 1）が表示されます。

<div class="example-output">

```text
+--------------------------------------+---------------------+--------+
| ID                                   | Name                | Status |
+--------------------------------------+---------------------+--------+
| 3f0c...                              | cirros-0.6.3-x86_64 | active |
+--------------------------------------+---------------------+--------+
```

</div>

:::note[出力例について]
このサイトの出力例は、説明のために書式を示したもので、実機から取得したログではありません。ID などの値は環境ごとに異なります。
:::

## 13. VM を作成する

```bash
openstack server create --flavor m1.tiny --image cirros-0.6.3-x86_64 \
    --network hagistack-tenant --key-name hagistack-key --wait demo1
```

- **意味：** テナントネットワークに接続した VM `demo1` を作り、キーペア `hagistack-key` の公開鍵を metadata 経由で注入します。`--wait` で起動完了まで待ちます。
- **セキュリティグループ：** 指定しない場合はプロジェクトの `default` が使われます。HAGISTACK は admin プロジェクトの `default` に SSH と ICMP を許可するルールを追加済みです。

## 14. VM が ACTIVE になったことを確認する

```bash
openstack server list
openstack server show demo1 -c status -c addresses
```

**期待される結果：** `status` が `ACTIVE` になり、`addresses` に `hagistack-tenant=10.10.10.x` が表示されます。
`ERROR` になった場合は [トラブルシューティング](/ja/operations/troubleshooting/) を参照してください。

起動ログ（cloud-init の出力）は次で確認できます。

```bash
openstack console log show demo1
```

## 15. Floating IP を割り当てる

```bash
openstack floating ip create hagistack-provider
openstack server add floating ip demo1 FLOATING_IP
```

- `FLOATING_IP` は 1 行目の出力にある `floating_ip_address` の値に置き換えます（例：`198.51.100.150`）。
- **期待される結果：** `openstack server show demo1 -c addresses` に、テナントのアドレスと Floating IP の両方が表示されます。

:::caution[Floating IP はそのままでは物理 LAN から届きません]
HAGISTACK は provider NIC を `br-ex` に接続しません。そのため、割り当てた Floating IP にはそのままでは外部から到達できません。
1 台で試す場合は、次の「SSH でログインする」の方法 B のように、ホスト自身の `br-ex` に provider ゲートウェイのアドレスを付けると、**そのホストから** Floating IP に到達できます（受入試験と同じ方法）。
物理 NIC を `br-ex` に接続して LAN から到達させる構成は、検証していません。
:::

## 16. セキュリティグループを確認する

```bash
SG=$(openstack security group list --project admin -f value -c ID -c Name | awk '$2=="default"{print $1}')
openstack security group rule list "$SG"
```

`default` という名前のセキュリティグループはプロジェクトごとにあり、名前だけでは 1 つに決まりません。そのため admin プロジェクトの `default` の ID を求めてから指定します（HAGISTACK 自身も同じ方法でルールを追加しています）。
**期待される結果：** `tcp` の `22:22` と `icmp` の ingress ルールがあります。

## 17. SSH で VM にログインする

CirrOS のユーザー名は `cirros` で、鍵は `/etc/hagistack/hagistack-key` です。ログイン経路は 2 通りあります。

### 方法 A：テナントアドレスに metadata の名前空間から接続する

VM が動いているホスト（All-in-one では同じホスト）には、テナントネットワークの OVN metadata 名前空間があります。そこから VM のテナントアドレスへ SSH できます。

```bash
NETID=$(openstack network show hagistack-tenant -f value -c id)
ip netns exec ovnmeta-$NETID ssh -i /etc/hagistack/hagistack-key cirros@TENANT_IP
```

`TENANT_IP` は手順 14 で表示された `10.10.10.x` のアドレスです。All-in-one の受入試験（s66r5c）で使った方法です。

### 方法 B：Floating IP に接続する（ホストから）

ホストの `br-ex` に provider ゲートウェイのアドレスを付けると、このホストから Floating IP に届きます。
`198.51.100.1/24` は例です。`--provider-gateway` と `--provider-cidr` で指定した値を使ってください。

```bash
ip addr add 198.51.100.1/24 dev br-ex
ip link set br-ex up
ssh -i /etc/hagistack/hagistack-key cirros@FLOATING_IP
```

Controller + Compute の受入試験（s66r5d）で使った方法です。
`ip addr add` の設定は再起動で消えます。本番の外部接続の作り方ではありません。

**期待される結果：** パスワードなしで `cirros` としてログインでき、`$` プロンプトが表示されます。VM 内で `curl http://169.254.169.254/latest/meta-data/instance-id` を実行すると、metadata サービスからインスタンス ID が返ります。

## 18. VM を停止・起動・削除する

```bash
openstack server stop demo1
openstack server show demo1 -c status      # SHUTOFF
openstack server start demo1
openstack server show demo1 -c status      # ACTIVE
openstack server delete --wait demo1
```

Floating IP は VM を削除しても残ります。不要になったら解放します。

```bash
openstack floating ip list
openstack floating ip delete FLOATING_IP
```

:::danger[削除は元に戻せません]
`server delete` と `floating ip delete` は取り消せません。対象の名前と ID を確認してから実行してください。
:::

## 次に読む

- [Horizon 操作ガイド](/ja/guides/horizon/)：同じ操作をブラウザで行う
- [Compute ノードの追加](/ja/guides/add-compute/)：2 台目のホストを追加する
- [OpenStack CLI ガイド](/ja/cli/overview/)：ユーザー、イメージ、ネットワークの管理
