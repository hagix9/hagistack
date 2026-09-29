# Hagistack for Ubuntu Server 26.04 LTS

[English](README.md) | 日本語

[← Hagistack の概要](../README.ja.md)

## 概要

`hagistack` は 1 本の Bash スクリプトです。
OpenStack 2026.1（Gazpacho）を Ubuntu 26.04 の公式アーカイブから導入します。
動作モードは 2 つです。

- **`all-in-one`**：コントロールプレーン全体とコンピュートサービスを、1 台のホストにまとめて導入します。
- **`compute-add`**：そのホストにコンピュートノードを追加します。

導入されるものは次のとおりです。

- **サービス：** Keystone、Glance、Placement、Nova（cells v2）、Neutron（ML2/OVN）
- **基盤：** Open vSwitch と OVN、MariaDB、RabbitMQ、memcached
- **ダッシュボード：** Horizon
- **初期リソース：** 最初のゲストがすぐに使える最小限のリソース（「[all-in-one が作成するもの](#all-in-one-が作成するもの)」を参照）

## 必要条件

**ホスト**

- **OS：** Ubuntu Server 26.04 LTS。これ以外の OS やバージョンは、preflight で拒否されます。
- **アーキテクチャ：**
  - `amd64` は検証済みです。
  - `arm64` も受け付け、対応する QEMU パッケージと CirrOS イメージを選びますが、**検証していません**。
- **権限：** `sudo` による root 権限
- **init システム：** systemd
- **メモリ：** all-in-one では 8 GiB 以上。8 GiB 未満だと preflight が警告します。
- **ディスク：** `/` に 40 GiB 以上の空きを推奨します。20 GiB 未満だと preflight が警告します。
- **仮想化：** `/dev/kvm` が使えれば `virt_type=kvm` になります。
  使えない場合は `qemu` のソフトウェアエミュレーションに切り替えます。
  エミュレーションは 10〜50 倍遅いので、起動の確認にしか向きません。
- **インターネット接続：**
  - パッケージの取得に Ubuntu の公式アーカイブ
  - 最初のゲストイメージの取得に `download.cirros-cloud.net`。ローカルのファイルを代わりに使うこともできます（`--image-file` を参照）。

**ネットワーク**

- **管理 IP。** サービスや他のノードが使うアドレスです。
  既定では、`1.1.1.1` への経路の送信元アドレスを使います。`--mgmt-ip` で上書きできます。
- **provider NIC（`--ext-nic`）。**
  - ホストに実在するインターフェースが必要です。
  - Hagistack はこの NIC を **provider ブリッジに接続しません**（「[既知の制約](#既知の制約)」を参照）。
  - NIC が 1 枚のホストでは、管理用 NIC を指定してもかまいません。
    preflight は警告を出しますが、Hagistack が管理アドレスを移動させることはありません。
- **provider ネットワークの値：**
  - CIDR
  - その CIDR 内のゲートウェイ
  - その CIDR 内の Floating IP の範囲。ゲートウェイはこの範囲の外に置きます。

**2 台目のノード**

- Ubuntu Server 26.04 LTS であること。
- コントローラとは異なるホスト名であること。
- コントローラの管理 IP に、次の TCP ポートで到達できること。
  - 5000（Keystone）
  - 9292（Glance）
  - 8778（Placement）
  - 5672（RabbitMQ）
  - 6642（OVN southbound）

  `compute-add` は、何かをインストールする前に、この 5 つをすべて確認します。
- ノード間の Geneve トンネルは **UDP 6081** を使います。このポートは確認しません。
- Hagistack はホストファイアウォールを設定しません。ファイアウォールを動かしている場合は、
  上記のポートを自分で開けてください。ファイアウォールが有効なホストでは検証していません。

## ファイル

| ファイル | 用途 |
|---|---|
| `hagistack` | インストーラ本体 |
| `hagistack.env.example` | コメント付きの設定ファイルの例。`hagistack.env` にコピーして使います |
| `tests/` | コンテナで実行する回帰テスト群（静的検査、入力の検証、設定の生成、再実行時の安全性）と、そのフィクスチャ |
| `STEP*_*.md`、`GCE_ACCEPTANCE_2026-09-28*.md` | 日付入りの開発記録と検証記録。**書かれた時点**の状態を記したもので、現在の状態を表すものではありません |

## 設定

各設定値は 4 つの層から与えられます。**優先順位**は次のとおりです。
コマンドライン > 環境変数 > 設定ファイル > 既定値

- **設定ファイル。** `--env-file` で指定したファイルを使います。
  指定がなければ、次のうち最初に見つかったものを使います。
  1. `./hagistack.env`
  2. スクリプトと同じディレクトリの `hagistack.env`
  3. `/etc/hagistack/hagistack.env`
- **設定ファイルをすべて無視する：** `--env-file /dev/null` を指定します。
- **`sudo` 経由で環境変数を渡す。** `sudo` は通常、環境変数を引き継がないので、明示的に渡します。
  `sudo env TENANT_CIDR=10.20.0.0/24 ./hagistack all-in-one …`
- **空の値。** どの層でも、空の値はエラーになります。「指定なし」とは扱いません。

| オプション | キー | 必須 | 既定値 |
|---|---|---|---|
| `--ext-nic NAME` | `EXT_NIC` | all-in-one | — |
| `--provider-cidr CIDR` | `PROVIDER_CIDR` | all-in-one | — |
| `--provider-gateway IP` | `PROVIDER_GATEWAY` | all-in-one | — |
| `--floating-start IP` | `FLOATING_START` | all-in-one | — |
| `--floating-end IP` | `FLOATING_END` | all-in-one | — |
| `--tenant-cidr CIDR` | `TENANT_CIDR` | | `10.10.10.0/24` |
| `--dns-server IP` | `DNS_SERVER` | | provider のゲートウェイ |
| `--provider-physnet NAME` | `PROVIDER_PHYSNET` | | `physnet1` |
| `--provider-bridge NAME` | `PROVIDER_BRIDGE` | | `br-ex` |
| `--image-name NAME` | `IMAGE_NAME` | | `cirros-0.6.3-x86_64`（amd64） |
| `--image-url URL` | `IMAGE_URL` | | CirrOS 0.6.3 のダウンロード URL |
| `--image-sha256 HEX` | `IMAGE_SHA256` | URL を変更したら必ず指定 | CirrOS が公開しているダイジェスト。ダウンロードしたファイルが一致しなければ拒否します |
| `--image-file PATH` | `IMAGE_FILE` | | —（ダウンロードせず、ローカルのファイルを使います） |
| `--controller-ip IP` | `CONTROLLER_IP` | compute-add | — |
| `--mgmt-ip IP` | `MGMT_IP` | | 自動検出 |
| `--virt-type kvm\|qemu` | `VIRT_TYPE` | | `/dev/kvm` から自動判定 |
| `--region-name NAME` | `REGION_NAME` | | `RegionOne` |

**設定ファイルは解析するだけで、実行しません。** 書けるのは次の行だけです。

- 空行
- `#` で始まるコメント
- 上の表にあるキーの `KEY=VALUE` 行

値に使える文字は、英字、数字と `. _ - : / @ + =` だけです。
未知のキー、重複したキー、シェルのメタ文字を含む値は拒否します。

**パスワードは書かないでください。** パスワードは Hagistack が自分で生成します
（「[機密ファイルと生成されるファイル](#機密ファイルと生成されるファイル)」を参照）。

all-in-one 用の最小限の `hagistack.env` の例です（値は仮のものです）。

```sh
EXT_NIC=eth1
PROVIDER_CIDR=192.0.2.0/24
PROVIDER_GATEWAY=192.0.2.1
FLOATING_START=192.0.2.100
FLOATING_END=192.0.2.200
```

## preflight チェック

```sh
git clone https://github.com/hagix9/hagistack.git
cd hagistack/ubuntu26.04
cp hagistack.env.example hagistack.env      # コピーしたら編集する
sudo ./hagistack all-in-one --check
```

`--check` は preflight だけを実行し、**何も変更しません**。確認する内容は次のとおりです。

- OS のバージョンとアーキテクチャ
- KVM と QEMU のどちらを使うか
- メモリとディスク
- provider NIC が存在すること
- 各アドレスと CIDR が正しく、互いに矛盾しないこと
  （ゲートウェイと Floating IP の範囲が CIDR 内にあり、ゲートウェイが範囲外にあること）
- 管理 IP
- イメージの入手元。ダウンロード URL は、SHA-256 ダイジェストが指定されていなければ拒否します。

最後に、最終的な各設定値と、その値の出どころ（コマンドライン、環境変数、ファイル、既定値）を表示します。

- 終了コード `0`：preflight に合格しました。
- 終了コード `1`：設定に誤りがあります。どの設定かはメッセージに示されます。

## all-in-one のインストール

```sh
sudo ./hagistack all-in-one
```

phase は次の順に実行されます。

1. preflight
2. secrets
3. 基本パッケージ
4. MariaDB
5. RabbitMQ
6. memcached
7. Keystone
8. Glance
9. Placement
10. OVS/OVN
11. Neutron
12. Nova
13. nova-compute
14. Horizon
15. 初期リソース

GCE の `n2-standard-4` では、新規のインストールに約 25 分かかりました。
完了時のバナーには、次のものが表示されます。

- ダッシュボードの URL
- admin の資格情報の場所
- テスト用ゲストを起動するコマンド
- コンピュートノードを追加するためのコマンド一式（このコントローラの管理 IP が入った形）

### all-in-one が作成するもの

各リソースは名前で確認し、なければ作成します。削除や作り直しはしません。

| リソース | 内容 |
|---|---|
| フレーバー | `m1.tiny`：1 vCPU、RAM 512 MiB、ディスク 1 GiB |
| イメージ | `cirros-0.6.3-x86_64`（amd64）。アップロードする**前に**、SHA-256 ダイジェストでファイルを検証します |
| 外部ネットワーク | `hagistack-provider`：`physnet1` 上の flat な external ネットワーク。サブネットは Floating IP の範囲を持ち、DHCP を使いません |
| テナントネットワーク | `hagistack-tenant`（Geneve） |
| ルータ | `hagistack-router`：provider ネットワーク側にゲートウェイを持ち、テナントのサブネットにインターフェースを持ちます |
| セキュリティグループのルール | admin プロジェクトの `default` グループに ICMP と TCP/22 を追加します |
| キーペア | `hagistack-key`（RSA 3072）。秘密鍵は `/etc/hagistack/hagistack-key` に mode `0600` で置きます |

## コンピュートノードの追加

各手順は、書かれているマシンで実行します。

**1. コントローラで：** コンピュートノードに必要な資格情報をファイルに書き出します。
このコマンドは端末への出力を拒否します。

```sh
(umask 077; sudo ./hagistack compute-secrets > compute-secrets.env)
```

`compute-secrets.env` を作るのは `hagistack` ではなくシェルなので、mode は umask で決まります。
上の `umask 077` によって、自分だけが読めるファイルになります。

このファイルに入るのは、次の 5 つの資格情報だけです。

- `RABBIT_PASS`
- `NOVA_SERVICE_PASS`
- `PLACEMENT_SERVICE_PASS`
- `NEUTRON_SERVICE_PASS`
- `METADATA_PROXY_SECRET`

データベースのパスワードや admin のパスワードは含まれません。

**2. 安全な経路でファイルを新しいノードにコピーし、** コントローラ側のコピーを削除します。

```sh
scp compute-secrets.env NODE:/tmp/
shred -u compute-secrets.env
```

**3. 新しいノードで：** 資格情報を配置し、コントローラの管理 IP を指定して `compute-add` を実行します。

```sh
sudo install -d -m 0750 /etc/hagistack
sudo install -o root -g root -m 0600 /tmp/compute-secrets.env /etc/hagistack/secrets.env
shred -u /tmp/compute-secrets.env
cd hagistack/ubuntu26.04
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP
```

`compute-add` は資格情報を生成しません。`/etc/hagistack/secrets.env` がなければ停止します。
何かをインストールする前に、次のことを確認します。

- `--controller-ip` がユニキャストアドレスとして使えるもので、このノード自身のアドレスではないこと
- コントローラが TCP 5000、9292、8778、5672、6642 で応答すること

このノードには、コントローラよりずっと少ないものしか渡しません。

- データベースへのアクセス権はありません。cell のデータベースには `nova-conductor` を経由してだけアクセスします。
- admin の資格情報はありません。
- provider ブリッジのマッピングはありません。

**4. コントローラに戻って：** 新しいホストを cell に登録します。

```sh
sudo ./hagistack discover-hosts
```

## 導入結果の確認

任意のノードで次を実行します。

```sh
sudo ./hagistack status
```

`status` は次のものを表示します。

- このホストの phase 完了マーカー
- all-in-one が完了しているか、未完了なら欠けている phase
- 各サービス unit の状態

コンピュートノードでは、コントローラで `discover-hosts` を実行するよう案内します。
ノード自身からは cell のデータベースが見えないためです。

コントローラでは、root として次を実行します。

```sh
sudo -i
. /etc/hagistack/admin-openrc
openstack compute service list
openstack hypervisor list
openstack network agent list
openstack server create --flavor m1.tiny --image cirros-0.6.3-x86_64 \
    --network hagistack-tenant --key-name hagistack-key demo1
openstack server show demo1 -c status
openstack console log show demo1        # cloud-init の出力
```

期待される結果は次のとおりです。

- ゲストが `ACTIVE` になります。検証したホストでは約 12〜18 秒でした。
- コンソールログに、cloud-init がメタデータを取得する様子が出ます。

`hagistack-tenant` 上のゲストは、Geneve を介してノードをまたいで互いに通信できます（検証済み）。
provider ブリッジに NIC を接続するまでは、物理 LAN には**到達できません**。

## Horizon

- **URL：** `http://MGMT_IP/horizon/`
- **Web サーバ：** API の vhost と同じ Apache が、ポート 80 で提供します。
- **ユーザー：** `admin`。パスワードは `/etc/hagistack/admin-openrc` の `OS_PASSWORD` です。
  Hagistack がパスワードを表示することはありません。
- **設定：** パッケージの設定が読み込むスニペットに書き込みます。
  パッケージ自身の `local_settings.py` は編集しません。
- **実行時の確認：** Horizon の phase は、実際に有効になっている Keystone の URL と
  キャッシュの接続先が、書き込んだ値どおりであることを確かめます。
  あわせて、ログインページが応答することも確認します。
- **`ALLOWED_HOSTS`：** パッケージの既定値（`['*']`）のままにします。
- **コンソールタブ：** noVNC プロキシを導入しないため、使えません。

**検証：** 2026-09-28 に GCE 上で、admin による実際のサインインを確認しました。
POST が 302 を返し、セッション cookie が発行され、保護されたページが `admin` として表示されました。
この確認は、同日 1 回目の受入実行で行ったものです。
現在のコードを生んだ 2 回目の実行では、サインインの確認を繰り返していません。

## Hagistack の再実行

`all-in-one` と `compute-add` は、再実行を前提に設計しています。
検証したホストでは、2 回目の実行は終了コード 0 で、すべての手順を「完了済み」と報告し、
どのサービスも再起動しませんでした。

再実行したときの動作は次のとおりです。

- **資格情報：** 既存のものを再利用し、変更しません。
- **データベース：** 削除しません。既存のデータベースには手を付けません。
- **設定ファイル：** キー単位で、値が変わるときだけ編集します。
  サービスを再起動するのは、設定が実行中のプロセスより新しい場合だけです。
- **初期リソース：** 名前で確認し、なければ作成します。削除や作り直しはしません。
- **基本パッケージ：** 一度導入したら次からは飛ばします。導入し直すには `HAGISTACK_REDO=1` を指定します。

Hagistack は**ロールバックしません**。実行が失敗した場合は、止まった行を表示します。
原因を直してから、同じコマンドをもう一度実行してください。

再実行は**設定変更のための手段ではありません**。
初回の実行後にアドレスや名前を変えても、既存のリソースやエンドポイントはそのまま残ります。
値の異なるエンドポイントについては警告を出しますが、書き換えはしません。

## コマンドリファレンス

```text
sudo ./hagistack all-in-one      [options]    このホストにコントローラとコンピュートを導入
sudo ./hagistack all-in-one --check [options] preflight のみ。何も変更しない
sudo ./hagistack compute-add --controller-ip IP [options]
sudo ./hagistack compute-secrets > FILE       コントローラで実行。端末への出力は拒否
sudo ./hagistack discover-hosts               コントローラで実行。新しいコンピュートホストを登録
sudo ./hagistack status                       phase の完了マーカーとサービスの状態
./hagistack --help | --version
```

両方のモードで使えるオプションは次のとおりです。

- `--mgmt-ip`
- `--virt-type`
- `--region-name`
- `--env-file`
- `--check`

`all-in-one` と `compute-add` のオプションは、「[設定](#設定)」の表にあります。

| 終了コード | 意味 |
|---|---|
| 0 | 成功 |
| 1 | 設定または preflight のエラー。あるいは、チェックに失敗して実行を止めた |
| 2 | 使い方の誤り（未知のコマンドやオプション） |
| 4 | 最後まで実行したが、依存するサービスに到達できず phase をスキップした。導入は**未完了**。原因を直して再実行する |
| その他の非ゼロ値 | あるコマンドが失敗した。Hagistack は `aborted at hagistack:LINE` を表示して止まる |

## 機密ファイルと生成されるファイル

| パス | 内容 | mode |
|---|---|---|
| `/etc/hagistack/secrets.env` | 生成したすべての資格情報。コンピュートノードでは、受け取った 5 つのキーだけ | `0600` |
| `/etc/hagistack/admin-openrc` | `openstack` CLI 用の admin 資格情報 | `0600` |
| `/etc/hagistack/hagistack-key` | キーペア `hagistack-key` の秘密鍵 | `0600` |
| `/var/lib/hagistack/state/*.done` | phase の完了マーカー。`status` と再実行時に使います | — |
| `/var/lib/openstack-dashboard/secret_key` | Horizon の Django 用シークレットキー | `0600` |
| `./hagistack.env` | あなたの設定。パスワードを書いてはいけません | — |
| `/etc/systemd/system/apache2.service.d/10-hagistack-procsubset.conf` | Apache の drop-in（「[トラブルシューティング](#トラブルシューティング)」を参照） | `0644` |

`secrets.env`、`admin-openrc`、`hagistack.env` はコミットしないでください。
リポジトリの `.gitignore` はこれらを除外しています。

## トラブルシューティング

- **終了コードが 4、または「INCOMPLETE」と表示される。**
  Hagistack が依存するサービスが応答しなかったため、phase をスキップしました。
  出力に、どの phase か、何を確認すればよいかが示されます。直してから再実行してください。
- **完了時のバナーに「NOTHING HERE IS VERIFIED ON REAL HARDWARE」と出る。**
  この見出しは GCE での検証より前の文言です。
  現在の状況は、見出しの下の行と「[検証環境](#検証環境)」を見てください。
- **ゲストが `VirtualInterfaceCreateException` で ERROR になる。**
  Apache の drop-in を確認します。

  ```sh
  systemctl show apache2 -p ProcSubset      # "all" であること
  ```

  Ubuntu 26.04 の `apache2.service` は `ProcSubset=pid` を設定しています。
  これにより Neutron API のワーカーから `/proc/meminfo` が見えなくなり、
  OVN のポートイベントがすべて捨てられます。
  Hagistack は `ProcSubset=all` にする drop-in を書き込み、
  ワーカーが `/proc/meminfo` を読めることを確かめます。
- **`compute-add` が「the controller is not reachable on: …」で止まる。**
  まだ何もインストールしていません。コントローラで、表示されたポートが待ち受けているか確認します。

  ```sh
  ss -ltn | grep -E '5000|9292|8778|5672|6642'
  ```

  次に、ファイアウォールがこのノードからの通信を遮っていないか確認します。
  OVN の southbound データベースはコントローラの管理 IP で待ち受けるので、
  `--controller-ip` にはそのアドレスを指定する必要があります。
- **ゲストが遅い、またはタイムアウトする。**
  preflight の出力で `virt_type` を確認します。`qemu` なら `/dev/kvm` が使えていません。

## 検証環境

Google Compute Engine 上の仮想マシン 2 台で、2026-09-28 に検証しました。

- **イメージ：** `ubuntu-2604-resolute-amd64`
- **仮想化：** ネスト仮想化を有効にし、`virt_type=kvm` で動作
- **node1：** n2-standard-4、ディスク 60 GB で `all-in-one`
- **node2：** n2-standard-2、ディスク 40 GB で `compute-add`

確認できたことは次のとおりです。

- すべての phase が完了した
- Keystone、Glance、Placement、Neutron、Nova への認証付き呼び出しが成功した
- cells v2 で両方のホストが登録された
- ノードごとに Placement のリソースプロバイダができた
- OVN のシャーシが 2 つ登録された
- 各ノードでゲストが ACTIVE になった（18 秒と 12 秒）
- cloud-init が完了した
- 別々のノード上のゲスト同士が ping で通信でき、そのパケットを Geneve トンネル上で捕捉した
- Horizon に admin でサインインできた（「[Horizon](#horizon)」を参照）
- `all-in-one` と `compute-add` の 2 回目の実行が、終了コード 0 で何も再起動しなかった

詳細は `GCE_ACCEPTANCE_2026-09-28.md` と `GCE_ACCEPTANCE_2026-09-28_RUN2.md` にあります。

## 既知の制約

**含まれないもの**

- **provider NIC の接続。** provider NIC を `br-ex` に**接続しません**。`br-ex` にアドレスも付けません。
  自分で NIC を接続するまで、provider ネットワークと Floating IP は物理 LAN に到達しません。
  NIC が 1 枚のホストで管理用 NIC を接続すると、管理アドレスが移動し、SSH が切れる可能性があります。
- **その他のサービス。** Cinder（ボリューム）、Swift などの OpenStack サービスは導入しません。
- **noVNC。** コンソールプロキシは導入しません。
- **ファイアウォール。** ホストファイアウォールは設定しません。
  API、RabbitMQ、OVN southbound データベース、memcached は管理ネットワーク上で待ち受けます。
  ノードは信頼できるネットワークに置いてください。

**未検証のもの**

- 物理 LAN を経由する経路と、ホストの外から Floating IP に到達すること
- ライブマイグレーション
- 3 台以上の構成
- `arm64`
- ホストファイアウォールが有効なホスト
