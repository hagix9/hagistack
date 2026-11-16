---
title: Compute ノードの追加
description: All-in-one に 2 台目の Rocky Linux 10.2 ホストを Compute ノードとして追加し、Nova cell への登録と VM の配置先を確認する。
sidebar:
  order: 2
---

[クイックスタート](/ja/quickstart/prepare/) で All-in-one を 1 台構築したあと、2 台目の Rocky Linux 10.2 ホストを Compute ノードとして追加します。

```text
Node 1: All-in-one（controller）
  Keystone / Glance / Placement / Nova API
  Neutron（OVN）/ Horizon
  Nova Compute / VM

           管理ネットワーク（例：192.0.2.0/24）

Node 2: Compute
  Nova Compute / libvirt / VM
  OVN Controller / OVN Metadata Agent
```

:::note[検証状況]
- **正式版の RPM での受入（2026-11-16、run s66r5d）：** Compute を持たない controller に Compute ノードを 1 台追加する構成で、登録、ゲストの起動、SSH、metadata、ノード間通信、Compute ノードの再起動と再登録、`compute-add` の再実行（何も変更しないこと）を確認しました。この試験は、公開 RPM と同じソース・同じ 195 パッケージ版から作り直したビルドで実施しています（バイト列は公開 RPM と一致しません）。
- **All-in-one + Compute ノード：** 2026-09-29 に、以前の RPM セットで GCE 上の 2 台構成を検証しています。
- **3 台以上の構成は検証していません。**
:::

## 1. 2 台目を準備する

| 項目 | 要件 |
|---|---|
| OS | Rocky Linux 10.2（x86_64） |
| ホスト名 | **controller と異なる**短いホスト名。Nova のホスト名と OVN の chassis 名に使われ、一致しないとポートを割り当てられません |
| 仮想化支援 | `/dev/kvm`（なければ qemu エミュレーション） |
| MTU | 管理インターフェースの MTU を controller と同じにする。小さいと、トンネル内で大きなパケットが落ちます |
| 時刻同期 | chronyd などで同期 |
| RPM セット | controller と**同じ RPM セット**。`compute-add` が確認し、違えば停止します |

2 台目から controller の管理 IP の次の TCP ポートに到達できる必要があります。

| ポート | 用途 |
|---|---|
| 5000 | Keystone |
| 9292 | Glance |
| 8778 | Placement |
| 9696 | Neutron API |
| 8775 | Nova metadata |
| 5672 | RabbitMQ |
| 6642 | OVN southbound |
| 11211 | memcached |

ノード間の Geneve トンネルは **UDP 6081** を双方向に使います（このポートは事前検査されません）。

HAGISTACK はファイアウォールを設定しません。`firewalld` が有効な場合（クラウドの Rocky Linux イメージなど）は、自分でポートを開けてください。

```bash
# controller で
sudo firewall-cmd --permanent --add-port={5000,9292,8778,9696,8775,5672,6642,11211}/tcp --add-port=6081/udp
# Compute ノードで
sudo firewall-cmd --permanent --add-port=6081/udp
# 両方で
sudo firewall-cmd --reload
```

送信元は管理ネットワークに限定してください。

:::tip[GCE とオンプレミスの違い]
- **GCE：** ネスト仮想化を有効にしたインスタンスが必要です。VPC のファイアウォールルールで、ノード間の上記ポートと UDP 6081 を許可します。受入試験は、ラン専用の VPC 内で外部 IP なしの 2 台を使って実施しました。
- **オンプレミス：** BIOS/UEFI で仮想化支援（VT-x / AMD-V）を有効にします。ノード間のスイッチやファイアウォールで、上記ポートと UDP 6081 を通します。
:::

2 台目にも同じ正式タグを取得しておきます。

```bash
sudo dnf -y install git
git clone --branch rocky10.2-rpms-2026.1 https://github.com/hagix9/hagistack.git
```

## 2. controller で資格情報を生成する

controller（Node 1）の `hagistack/rocky10.2` で実行します。

```bash
(umask 077; sudo ./hagistack compute-secrets > compute-secrets.env)
```

- **内容：** Compute ノードに必要な 5 つの資格情報（`RABBIT_PASS`、`NOVA_SERVICE_PASS`、`PLACEMENT_SERVICE_PASS`、`NEUTRON_SERVICE_PASS`、`METADATA_PROXY_SECRET`）と、controller の RPM セット ID（`RPM_SET_SHA256`、秘密ではありません）。データベースのパスワードと admin のパスワードは含みません。
- **権限：** ファイルを作るのは `hagistack` ではなくシェルです。`umask 077` で自分だけが読めるファイルになります。`compute-secrets` は端末への出力を拒否します。

:::danger[資格情報の扱い]
このファイルは機密情報です。メールやチャットで送らず、`scp` など暗号化された経路で転送し、転送後は controller 側のコピーを削除してください。
:::

## 3. Compute ノードに資格情報を配置する

```bash
# controller で：転送して削除
scp compute-secrets.env NODE2:/tmp/
shred -u compute-secrets.env
```

```bash
# Compute ノード（Node 2）で
sudo install -d -m 0700 /etc/hagistack
sudo install -o root -g root -m 0600 /tmp/compute-secrets.env /etc/hagistack/secrets.env
shred -u /tmp/compute-secrets.env
```

`/etc/hagistack/secrets.env` は root:root、モード `0600` になります。

## 4. Compute ノードを追加する

Compute ノードの `hagistack/rocky10.2` で実行します。

```bash
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP
```

`CONTROLLER_MGMT_IP` は controller の管理 IP（例：`192.0.2.10`）です。

| controller の RPM の取得方法 | Compute ノードのコマンド |
|---|---|
| 公開リリース（`github`、既定） | `sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP` |
| ソースからビルド（`build`） | controller で `sudo ./hagistack rpm-bundle --output /root/hagistack-rpms.tar` を作り、ノードへコピーしてから `sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP --rpm-source bundle --rpm-bundle /root/hagistack-rpms.tar` |
| 自前のリポジトリ（`--repo-url`） | `sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP --repo-url URL` |

`compute-add` は次のように動きます。

- `/etc/hagistack/secrets.env` がない、または有効な `RPM_SET_SHA256` がない場合は停止します。シークレットを生成することはありません。
- 何かを変更する**前に**、controller のポートに到達できるか確認します。
- このノードの RPM セットが controller と異なる場合は、パッケージを入れる前に停止します（RPM セットの一致確認）。
- このノードにはデータベースへの接続設定、admin の資格情報、provider のブリッジマッピングを置きません。

## 5. Nova cell へ登録する

controller で実行します。

```bash
sudo ./hagistack discover-hosts
```

新しい Compute ホストを Nova の cell に登録します。controller は 300 秒ごとに自動でも登録しますが、すぐ使いたい場合はこのコマンドを実行します。

## 6. 2 台の Compute を確認する

controller で実行します。

```bash
sudo -i
. /etc/hagistack/admin-openrc
openstack compute service list --service nova-compute
openstack hypervisor list
```

**期待される結果：** `nova-compute` が 2 行（Node 1 と Node 2）あり、どちらも `State` が `up`、`Status` が `enabled` です。`hypervisor list` にも 2 台が `up` で表示されます。

ネットワーク側も確認できます。

```bash
openstack network agent list
```

Node 2 の `OVN Controller agent` と `OVN Metadata agent` が `Alive` = `True` になります。

## 7. VM がどちらのノードで動いているか確認する

```bash
openstack server list
openstack server show demo1 -c name -c status -c OS-EXT-SRV-ATTR:host
```

`OS-EXT-SRV-ATTR:host` に、その VM が動いている Compute ホストの名前が表示されます。
この項目は既定のポリシーでは**管理者だけ**が見られます。一般ユーザーには表示されません。

ホストごとの一覧は次で確認できます。

```bash
openstack server list --all-projects --host NODE2_HOSTNAME
```

## 8. VM の配置について

VM をどのホストに置くかは **Nova スケジューラー** が決めます。

1. **フィルター：** 空き RAM・ディスク・vCPU、稼働状態などの条件を満たさないホストを除外します。
2. **重み付け：** 残ったホストに点数を付け、最も点数の高いホストを選びます。

そのため、Compute が 2 台あっても、VM が交互に、あるいは均等に配置されるとは限りません。
HAGISTACK はスケジューラーの設定を既定値のまま使っています。

管理者は、作成時に配置先を指定できます（OpenStack 2026.1 の CLI 構文）。

```bash
# 可用性ゾーンとホストで指定
openstack server create --flavor m1.tiny --image cirros-0.6.3-x86_64 \
    --network hagistack-tenant --key-name hagistack-key \
    --availability-zone nova:NODE2_HOSTNAME demo2

# compute API 2.74 以上でホストを指定
openstack --os-compute-api-version 2.74 server create --flavor m1.tiny \
    --image cirros-0.6.3-x86_64 --network hagistack-tenant \
    --key-name hagistack-key --host NODE2_HOSTNAME demo3
```

:::caution[未検証の操作]
上の配置先指定は、OpenStack 2026.1 の CLI（python-openstackclient 9.0.1）が提供する構文で、いずれも**管理者だけ**が使えます。HAGISTACK の受入試験では実行していません。
作成済みの VM を別のホストへ移す**マイグレーション**と**ライブマイグレーション**は別の機能です。HAGISTACK では検証しておらず、対応機能としては扱いません。
:::

## 9. トラブルシューティング

| 症状 | 確認すること |
|---|---|
| Compute が登録されない | controller で `sudo ./hagistack discover-hosts` を実行。Node 2 で `sudo ./hagistack status` を確認 |
| `nova-compute` が `down` になる | Node 2 で `sudo journalctl -u openstack-nova-compute -n 100`。RabbitMQ（5672）に届くか、時刻が同期しているか |
| `hypervisor list` に出ない | `openstack compute service list --service nova-compute` で `up` か。`discover-hosts` を実行したか |
| VM が `ERROR` になる | `openstack server show VM -c fault`。`Refusing to bind port … no OVN chassis for host` はホスト名と chassis 名の不一致（ホスト名が一意で安定しているか確認して再実行） |
| 2 台目に VM が配置されない | 2 台目の `nova-compute` が `up` か、空きリソースは十分か。スケジューラーは必ずしも分散しません |
| RPM セットが一致しない | controller と同じ方法・同じタグで取得しているか。`compute-secrets` を controller の現在の版で作り直したか |
| `compute-add` が「the controller is not reachable on every port」で止まる | 何もインストールされていません。表示されたポートを controller とその間のファイアウォールで確認 |

詳しくは [トラブルシューティング](/ja/operations/troubleshooting/) を参照してください。
