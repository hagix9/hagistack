# Hagistack for Rocky Linux 10.2

[English](README.md) | 日本語

[← Hagistack の概要](../README.ja.md)

> **最初に OpenStack の RPM リポジトリをビルドしてください。**
> Rocky Linux には OpenStack が含まれていません。
> EL10 向けの OpenStack 2026.1 は、RDO のリリースリポジトリとしても、
> CentOS Cloud SIG からも公開されていません。
> そのため、2026.1 の RPM は `build-rpms.sh` で自分でビルドします
> （「[RPM リポジトリのビルド](#rpm-リポジトリのビルド)」を参照）。
> その成果物を `--repo-url` でインストーラに指定します。
> このリポジトリがなければ、`hagistack` はインストールを行いません。

## 概要

`hagistack` は 1 本の Bash スクリプトです。
リリース版の 2026.1 tarball から自分でビルドした RPM リポジトリを使い、
Rocky Linux 10.2 に OpenStack 2026.1（Gazpacho）を導入します。動作モードは 2 つです。

- **`all-in-one`**：コントロールプレーン全体とコンピュートサービスを、1 台のホストにまとめて導入します。
- **`compute-add`**：そのホストにコンピュートノードを追加します。

導入されるものは次のとおりです。

- **サービス：** Keystone、Glance、Placement、Nova（cells v2）、Neutron（ML2/OVN）
- **基盤：** Open vSwitch と OVN、MariaDB、RabbitMQ、memcached
- **ダッシュボード：** Horizon
- **初期リソース：** 最初のゲストがすぐに使える最小限のリソース

## 必要条件

**ホスト**

- **OS：** Rocky Linux 10.2
  - 他の EL10 系（RHEL、AlmaLinux、CentOS 10）では警告を出して処理を続けますが、**検証していません**。
  - それ以外は拒否します。
- **アーキテクチャ：** x86_64 のみ。それ以外は拒否します。
- **権限：** `sudo` による root 権限
- **init システム：** systemd
- **メモリ：** all-in-one では 8 GB 以上。約 7 GB 未満だと preflight が警告します。
- **ディスク：** `/` に 20 GB 以上の空き。検証に使った all-in-one ノードは 60 GB でした。
- **仮想化：** `/dev/kvm` が読めれば `virt_type=kvm` になります。
  読めない場合は `qemu` のソフトウェアエミュレーションに切り替えます（10〜50 倍遅くなります）。
- **SELinux：ホストを permissive に切り替えます。** 検証したのはこのモードだけです。
  - Hagistack は `httpd_can_network_connect` を有効にします。
  - 続けて `setenforce 0` を実行し、`/etc/selinux/config` に `SELINUX=permissive` を書き込むので、再起動後も permissive のままです。
  - SELinux が `Disabled` の場合は、報告するだけで変更しません。`Disabled` は検証した構成ではありません。
  - **enforcing モードは検証していません。**
    RDO が OpenStack 用に出している SELinux ポリシー（`openstack-selinux`）は
    RDO の OpenStack コンポーネントリポジトリでしか公開されておらず、
    Hagistack はそのリポジトリを有効にしないためです。
- **2026.1 の RPM リポジトリ：** 各ノードから `--repo-url` で到達できること。
- **依存リポジトリのためのインターネット接続。** Hagistack は次のものを追加します。
  - EPEL 10（あわせて CRB を有効にします）
  - Open vSwitch と OVN のための CentOS Stream 10 NFV SIG のミラー
  - RDO の EL10 向けサードパーティ依存リポジトリ（Python ライブラリ、RabbitMQ/Erlang）
  - 最初のゲストイメージのための `download.cirros-cloud.net`（`--image-file` を指定した場合は不要）

**ネットワーク**

- **管理 IP。** サービスや他のノードが使うアドレスです。
  既定では、`8.8.8.8` への経路の送信元アドレスを使います。`--mgmt-ip` で上書きできます。
- **provider NIC（`--ext-nic`）。** ホストに実在するインターフェースが必要です。
  Hagistack はこの NIC を **provider ブリッジに接続しません**（「[既知の制約](#既知の制約)」を参照）。
- **provider ネットワークの値：** CIDR、その中のゲートウェイ、その中の Floating IP の範囲
- **ホスト名。** 各ノードに**互いに異なる短いホスト名**が必要です。
  Nova のホスト名と OVN のシャーシ名はどちらも短いホスト名に設定され、
  ポートを割り当てるには両者が一致している必要があります。

**2 台目のノード**

- Rocky Linux 10.2 x86_64 で、同じ RPM リポジトリにアクセスできること。
- コントローラの管理 IP に、次の TCP ポートで到達できること。
  - 5000（Keystone）
  - 9292（Glance）
  - 8778（Placement）
  - 5672（RabbitMQ）
  - 6642（OVN southbound）
  - 11211（memcached）
- ノード間の Geneve トンネルは **UDP 6081** を使います。このポートは確認しません。
- Hagistack はホストファイアウォールを設定しません。
  `firewalld` などが有効な場合は、上記のポートを自分で開けてください。その構成は検証していません。

## インストールの流れ

```text
 ビルド用 VM（使い捨て）                        各 OpenStack ノード
 ─────────────────────────                    ───────────────────────────────
 build-rpms.sh + gazpacho.manifest            hagistack all-in-one / compute-add
   → 固定した distgit と tarball                 --repo-url <作成したリポジトリ>
   → rpmbuild                                   → そのリポジトリから dnf install
   → createrepo_c  ──── コピーまたは配信 ────▶     ＋ Rocky、EPEL、NFV SIG、RDO の依存リポジトリ
```

**OpenStack のパッケージは、すべて自分でビルドした 2026.1 リポジトリから入ります。**
このリポジトリは `priority=1` で登録します。
RDO の OpenStack コンポーネントリポジトリ（`delorean-component-*`）はトランクのスナップショットを含むため、
Hagistack は追加しません。有効になっている場合は警告を出します。

サードパーティの Python ライブラリは RDO の依存ツリーから入り、バージョンは EL10 にあるものになります。
これらは OpenStack の成果物ではありません。

## RPM リポジトリのビルド

`build-rpms.sh` は、`gazpacho.manifest` に記載されたパッケージをビルドします。

- keystone 29.1.0、glance 32.0.0、placement 15.0.0、neutron 28.0.2、nova 33.0.2、horizon 25.7.3
- これらが必要とする OpenStack のライブラリとクライアント（2026.1 のバージョン）
- Horizon が必要とし、EL10 に含まれていない静的アセットやユーティリティのパッケージ 10 個

**実行する場所。** **使い捨ての Rocky Linux 10.2 x86_64 の VM かコンテナ**で実行してください。
OpenStack ノードでは実行しないでください。root 権限で次のことを行います。

- ビルド依存パッケージの導入（`sudo dnf builddep`）
- `/etc/yum.repos.d/hagistack-gazpacho.repo` の書き込み
- RDO のリポジトリファイルがあれば、そこへの `exclude=` 行の追加

記録に残っているビルドは、標準の Rocky Linux 10.2 イメージを使った GCE の `n2-standard-4` 上で行いました。

**ビルド環境の準備：**

- `sudo` を使えるユーザー
- `git`、`curl`、`rpm-build`、`rpmdevtools`、`createrepo_c`
- `dnf builddep` がビルド依存を解決できるリポジトリ

`build-rpms.sh` は、ビルド環境のリポジトリを**設定しません**。
記録に残っているビルドでは、ビルド依存の取得に Rocky の BaseOS/AppStream/CRB、EPEL 10、
RDO の EL10 用リポジトリファイル（`delorean.repo`、`delorean-deps.repo`）を使いました。

**実行方法：**

```sh
git clone https://github.com/hagix9/hagistack.git
cd hagistack/rocky10.2
./build-rpms.sh --nocheck                 # gazpacho.manifest の全パッケージ
./build-rpms.sh --nocheck keystone        # または、指定したパッケージだけ
```

**ビルド前に検証すること。** どれか 1 つでも一致しなければ、**ビルドを止めます**。
「最新版」で代用することはありません。

- 各 distgit を、manifest に記載したコミットでチェックアウトし、チェックアウト後にコミットを照合します。
- OpenStack の各 tarball が、SHA-256 ダイジェストと一致することを確認します。
- spec の `%prep` が、manifest に記載した OpenStack リリース鍵で tarball の GPG 署名を検証します。
- Horizon 用の PyPI からの入力 10 個には**署名がありません**。SHA-256 だけで固定しています。
- RDO の master の spec がリリース版 tarball と合わない箇所は、
  `spec-patches/` にあるレビュー可能なパッチで修正します。適用できないパッチがあればビルドを止めます。
  `spec-templates/` には、PyPI パッケージ用のテンプレートが 1 つ入っています。
- Neutron だけは「リリース版 tarball をそのまま使う」の例外です。
  `spec-patches/neutron.patch` は、2026.1 のどのリリースにも入っていない上流の
  Neutron コミット `83f1d830` と `91abb5e7` の 2 つも追加します。
  これらは、OVN メンテナンスワーカーがデータベースのロックを持たないまま動き続けることがある競合を修正します。
  そのため Neutron の RPM はリリース `2`（`28.0.2-2`）です。
  修正は `tests-neutron-maintenance-lock.py` で確認します。

**成果物。**

| 内容 | 場所 |
|---|---|
| RPM とリポジトリのメタデータ（`createrepo_c`） | `~/rpmbuild/RPMS/`。`REPO_PUBLISH_DIR` で別のディレクトリに公開できます（既存のリポジトリにパッケージを追加する場合など） |
| ビルドログ | `~/epoxy-build/logs/`。基準のディレクトリは `WORK` で変えられます |
| ビルド環境のロック（ビルド環境にあるすべての RPM の一覧） | `~/epoxy-build/build-env.lock` |

どれか 1 つでもパッケージのビルドに失敗すると、スクリプトは非ゼロで終了します。
`--publish` はリポジトリ作成の手順だけを、`--lock` はロックファイルだけを作り直します。

**`%check` の状況。**

- `--nocheck` は各パッケージのテストスイートを省略します。
  **検証に使った x86_64 の RPM は `--nocheck` でビルドしたので、`%check` は一度も実行していません。**
- `--nocheck` を付けなければテストスイートを実行します。
  非常に大きなものもあります（os-ken は約 121,000 件、neutron は約 21,000 件）。

`epoxy.manifest` と `build-keystone-epoxy.sh` は、以前の 2025.1 ビルドの記録で、現在は使いません。
`probe-repos.sh` は、公開されている EL10 向け OpenStack リポジトリを読み取り専用で調べ直すツールです。
そのメッセージが参照しているのはこの README の旧版の節で、旧版は Git の履歴にあります。

## リポジトリを利用可能にする

`--repo-url` の値は、各ノードの `/etc/yum.repos.d/hagistack-gazpacho.repo` の `baseurl` になります。
ノードはそこから `openstack-keystone` を解決できなければならず、インストーラは先に進む前にそれを確認します。
使える形式は 2 つです。

- **ローカルのディレクトリ。** 公開したディレクトリを `repodata/` ごと各ノードにコピーし、
  file URL として指定します。

  ```sh
  # ビルド用 VM で
  rsync -a ~/rpmbuild/RPMS/ NODE:/opt/hagistack-repo/
  # ノードで
  --repo-url file:///opt/hagistack-repo
  ```

- **HTTP(S) サーバ。** ディレクトリを配信し、その URL を指定します。
  `--repo-url https://repo.example.internal/hagistack-gazpacho/`

このリポジトリは `gpgcheck=0` で登録するので、**RPM には署名がありません**。
Hagistack が追加する依存リポジトリも `gpgcheck=0` です。
リポジトリの完全性は、どうコピーまたは配信するかにかかっています。

## 設定

設定値は **コマンドライン** か **設定ファイル** で与えます。コマンドラインが優先します。

- **設定ファイル。** `--env-file` で指定したファイルを使います。
  指定がなければ、次のうち最初に見つかったものを使います。
  1. `./hagistack.env`
  2. スクリプトと同じディレクトリの `hagistack.env`
  3. `/etc/hagistack/hagistack.env`
- **ファイルの形式** は Ubuntu と同じです。解析するだけで、実行しません。
  書けるのは、空行、`#` で始まるコメント、下の表にあるキーの `KEY=VALUE` 行だけです。
  値に使える文字は、英字、数字と `. _ - : / @ + =` だけです。
- **設定ファイルにパスワードは書かないでください。**
- **Rocky 用スクリプトは環境変数を読みません。** オプションかファイルを使ってください。

| オプション | キー | 必須 | 既定値 |
|---|---|---|---|
| `--repo-url URL` | `REPO_URL` | all-in-one、compute-add | — |
| `--ext-nic NAME` | `EXT_NIC` | all-in-one | — |
| `--provider-cidr CIDR` | `PROVIDER_CIDR` | all-in-one | — |
| `--provider-gateway IP` | `PROVIDER_GATEWAY` | all-in-one | — |
| `--floating-start IP` | `FLOATING_START` | all-in-one | — |
| `--floating-end IP` | `FLOATING_END` | all-in-one | — |
| `--tenant-cidr CIDR` | `TENANT_CIDR` | | `10.10.10.0/24` |
| `--dns-server IP` | `DNS_SERVER` | | provider のゲートウェイ |
| `--provider-physnet NAME` | `PROVIDER_PHYSNET` | | `physnet1` |
| `--provider-bridge NAME` | `PROVIDER_BRIDGE` | | `br-ex` |
| `--image-name NAME` | `IMAGE_NAME` | | `cirros-0.6.3-x86_64` |
| `--image-url URL` | `IMAGE_URL` | | CirrOS 0.6.3 のダウンロード URL |
| `--image-sha256 HEX` | `IMAGE_SHA256` | URL を変更したら必ず指定 | CirrOS が公開しているダイジェスト |
| `--image-file PATH` | `IMAGE_FILE` | | —（ダウンロードせず、ローカルのファイルを使います） |
| `--controller-ip IP` | `CONTROLLER_IP` | compute-add | — |
| `--mgmt-ip IP` | `MGMT_IP` | | 自動検出 |
| `--virt-type kvm\|qemu` | `VIRT_TYPE` | | `/dev/kvm` から自動判定 |
| `--region-name NAME` | `REGION_NAME` | | `RegionOne` |

`--provider-physnet` と `--provider-bridge` は、`--help` の一覧には出ませんが使えます。

`hagistack.env` の例です（値は仮のものです）。

```sh
REPO_URL=file:///opt/hagistack-repo
EXT_NIC=eth1
PROVIDER_CIDR=192.0.2.0/24
PROVIDER_GATEWAY=192.0.2.1
FLOATING_START=192.0.2.100
FLOATING_END=192.0.2.200
```

## preflight チェック

```sh
cd hagistack/rocky10.2
sudo ./hagistack all-in-one --check --repo-url file:///opt/hagistack-repo \
    --ext-nic eth1 --provider-cidr 192.0.2.0/24 --provider-gateway 192.0.2.1 \
    --floating-start 192.0.2.100 --floating-end 192.0.2.200
```

`--check` は preflight だけを実行し、**何も変更しません**。確認する内容は次のとおりです。

- OS とアーキテクチャ
- 管理 IP
- provider NIC が存在すること
- provider のアドレス（ゲートウェイと Floating IP の範囲が CIDR 内にあること）
- テナントの CIDR、DNS サーバ、リージョン
- `virt_type`
- ディスクとメモリ

最後に、最終的な各設定値とその出どころを表示します。

`--check` では次のことは**確認しません**。インストーラがその段階に達したときに確認します。

- `--repo-url` が使えるかどうか（リポジトリの phase で確認）
- `compute-add` の場合、コントローラのポートに到達できるかどうか（コンピュート用 preflight で確認）

## all-in-one のインストール

```sh
sudo ./hagistack all-in-one --repo-url file:///opt/hagistack-repo   # ほかの設定もあわせて指定
```

phase は次の順に実行されます。

1. preflight
2. リポジトリ
3. SELinux
4. secrets
5. パッケージ
6. MariaDB
7. RabbitMQ
8. memcached
9. Keystone
10. Glance
11. Placement
12. OVS/OVN
13. Neutron
14. Nova
15. nova-compute
16. 初期リソース
17. Horizon

各 API の動かし方は次のとおりです。

- **Web サーバ（`httpd`、mod_wsgi）：** Keystone、Placement、Neutron の API、
  Nova の compute API とメタデータ API
- **独自の unit：** Glance
- **無効化するもの：** 2026.1 では提供されなくなったバイナリを指すパッケージ付属の unit
  （`neutron-server` と Nova の API 用 unit）

完了時のバナーには、admin の資格情報の場所、ダッシュボードの URL、
コンピュートノードを追加するためのコマンド一式が表示されます。

**all-in-one が作成するもの。** 各リソースは名前で確認し、なければ作成します。

| リソース | 内容 |
|---|---|
| フレーバー | `m1.tiny`：1 vCPU、RAM 256 MiB、ディスク 1 GiB |
| イメージ | `cirros-0.6.3-x86_64`。アップロード前に SHA-256 ダイジェストで検証し、そのダイジェストをタグとして付けます |
| 外部ネットワーク | `hagistack-provider`：`physnet1` 上の flat な external ネットワーク。サブネットは Floating IP の範囲を持ち、DHCP を使いません |
| テナントネットワーク | `hagistack-tenant`（サブネット `hagistack-tenant-subnet`） |
| ルータ | `hagistack-router`：provider ネットワーク側にゲートウェイを持ち、テナントのサブネットにインターフェースを持ちます |
| セキュリティグループのルール | admin プロジェクトの `default` グループに SSH と ICMP を追加します |
| キーペア | `hagistack-key`（Nova が生成）。秘密鍵は `/etc/hagistack/hagistack-key` に mode `0600` で置きます |

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

**3. 新しいノードで：** 資格情報を配置します。
RPM リポジトリも利用できるようにしておきます（「[リポジトリを利用可能にする](#リポジトリを利用可能にする)」を参照）。

```sh
sudo install -d -m 0700 /etc/hagistack
sudo install -o root -g root -m 0600 /tmp/compute-secrets.env /etc/hagistack/secrets.env
shred -u /tmp/compute-secrets.env
```

**4. 新しいノードで：** `compute-add` を実行します。

```sh
cd hagistack/rocky10.2
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP \
    --repo-url file:///opt/hagistack-repo
```

`compute-add` は資格情報を生成しません。`/etc/hagistack/secrets.env` がなければ停止します。

リポジトリの設定と SELinux の permissive への切り替えは、
コントローラのポートに到達できるかを確認する**前に**行います。
この確認に失敗した場合、パッケージはインストールしませんが、この 2 つの変更はすでに行われています。

このノードには、データベースへのアクセス権はありません（`nova.conf` のデータベース接続のキーはコメントアウトします）。
admin の資格情報も、provider ブリッジのマッピングもありません。

**5. コントローラに戻って：** 新しいホストを cell に登録します。

```sh
sudo ./hagistack discover-hosts
```

## 導入結果の確認

```sh
sudo ./hagistack status
```

`status` は次のものを表示します。

- phase の完了マーカー
- SELinux の現在のモードと起動時のモード、および Hagistack が SELinux に何をしたか
- 各サービス unit の状態

表示のうち `stage` と `unverified` の行は古い内容です（「[トラブルシューティング](#トラブルシューティング)」を参照）。

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

**Horizon のサインインテスト。** `tests-horizon-login.sh` は、admin による実際のサインインを確認します。
次のすべてが成り立ったときだけ PASS になります。

- ログインの POST がリダイレクトを返す
- セッション cookie が発行される
- 保護されたページが `admin` として表示される
- 2 つの異常系のテストが、想定どおり失敗する

パスワードは `/etc/hagistack/admin-openrc` から読み、コマンドラインに出すことはありません。

```sh
sudo ./tests-horizon-login.sh
# 別のアドレスを使う場合：
sudo HZ_URL=http://MGMT_IP/dashboard ./tests-horizon-login.sh
```

終了コードは、`0` が PASS、`1` が FAIL、`2` がスクリプトを実行できなかったことを表します。

## Horizon

- **URL：** `http://MGMT_IP/dashboard/`。`httpd` がポート 80 で提供します。
- **ユーザー：** `admin`。パスワードは `/etc/hagistack/admin-openrc` の `OS_PASSWORD` です。
- **設定：** Hagistack は `/etc/openstack-dashboard/local_settings` に、目印を付けたブロックを追記します。
  静的アセットを再構築するのは、そのブロックが変わったときだけです。
- **httpd の drop-in：** `/usr/share/openstack-dashboard` への書き込みを許可する drop-in を追加します。
  ダッシュボードのパッケージが起動時に行う処理に、`ProtectSystem` のもとで必要になるためです。
- **`ALLOWED_HOSTS`：** `['*']`
- **コンソールタブ：** noVNC プロキシを導入しないため、使えません。

2026-09-29 に GCE 上で**検証済み**です。結果は次のとおりでした。

- ログインページが 200 を返した
- POST が 302 を返した
- セッション cookie が発行された
- 保護された 4 つのページが、ログインフォームなしで `admin` として 200 を返した
- `all-in-one` を再実行しても何も再構築・再起動されず、サインインも引き続き成功した

この結果は `tests-horizon-login.sh` の最初の版で得たものです。
より厳密にした現在の版は、ローカルのフィクスチャで確認しただけで、**実際の Horizon に対してはまだ実行していません。**

## Hagistack の再実行

`all-in-one` と `compute-add` は、再実行を前提に設計しています。

- 検証した all-in-one ノードでは、2 回続けて実行しても終了コードは 0 でした。
  スキップした phase も、再起動した unit もなく、ダッシュボードのアセットも再構築されませんでした。
- 2 回目の `compute-add` も終了コード 0 で、何も再起動しませんでした。

再実行したときの動作は次のとおりです。

- **資格情報：** 既存のものを再利用し、変更しません。
- **データベース：** 削除しません。
- **設定ファイル：** キー単位で編集します。サービスを再起動するのは、設定が実行中のプロセスより新しい場合だけです。
- **初期リソース：** 名前で確認し、なければ作成します。
- **リポジトリのファイル：** 内容が違うときだけ書き直します。

Hagistack は**ロールバックしません**。失敗したら原因を直し、同じコマンドをもう一度実行してください。

再実行は設定変更のための手段ではありません。既存のリソースやエンドポイントはそのまま残ります。

## コマンドリファレンス

```text
sudo ./hagistack all-in-one  --repo-url URL [options]
sudo ./hagistack all-in-one  --check [options]         preflight のみ。何も変更しない
sudo ./hagistack compute-add --controller-ip IP --repo-url URL [options]
sudo ./hagistack compute-secrets > FILE                コントローラで実行。端末への出力は拒否
sudo ./hagistack discover-hosts                        コントローラで実行。新しいコンピュートホストを登録
sudo ./hagistack status                                phase、SELinux、サービスの状態
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
| その他の非ゼロ値 | あるコマンドが失敗し、その時点で実行が止まった |

## 機密ファイルと生成されるファイル

| パス | 内容 | mode |
|---|---|---|
| `/etc/hagistack/` | Hagistack の設定ディレクトリ | `0700` |
| `/etc/hagistack/secrets.env` | 生成したすべての資格情報（Horizon のシークレットキーを含む）。コンピュートノードでは、受け取った 5 つのキーだけ | `0600` |
| `/etc/hagistack/admin-openrc` | `openstack` CLI 用の admin 資格情報 | `0600` |
| `/etc/hagistack/hagistack-key` | キーペア `hagistack-key` の秘密鍵 | `0600` |
| `/var/lib/hagistack/state/` | phase の完了マーカーと、SELinux に対して行ったことの記録 | — |
| `/etc/yum.repos.d/hagistack-*.repo` | Hagistack が追加したリポジトリ | — |
| `/etc/selinux/config` | `SELINUX=permissive` に設定されます | — |
| `./hagistack.env` | あなたの設定。パスワードを書いてはいけません | — |

## トラブルシューティング

- **`--repo-url is required on Rocky` と出る、またはリポジトリが「does not offer openstack-keystone」と出る。**
  URL は、`repodata/` を持つディレクトリ（`createrepo_c` を実行済みのもの）を指している必要があります。
  このノードから読めることも必要です。
- **`delorean-component-*` のリポジトリが有効だという警告が出る。**
  次のコマンドで無効にします。

  ```sh
  dnf config-manager --set-disabled 'delorean-component-*'
  ```

  有効なままだと、導入されるのは単一の OpenStack リリースではなくなります。
- **ゲストが「Refusing to bind port … no OVN chassis for host」で失敗する。**
  そのノードの Nova のホスト名と OVN のシャーシ名が一致していません。
  Hagistack は両方を短いホスト名に設定します。
  各ノードに、互いに異なり変わらない短いホスト名があることを確認してから、再実行してください。
- **`error:` の行が出ないまま実行が止まる。**
  Rocky 用スクリプトは、止まった行を表示しないことがあります。
  出力の最後にある `==>` の手順が、失敗した phase です。
- **`status` が Horizon を未検証と表示し、`--help` が Horizon を扱わないと書いている。**
  どちらも Horizon の作業より前の文言です。
  Horizon の phase は実行され、サインインも検証済みです（「[Horizon](#horizon)」を参照）。
- **`compute-add` が「the controller is not reachable on every port」で止まる。**
  パッケージはまだインストールしていません。
  コントローラで表示されたポートを確認し、2 台の間のファイアウォールも確認してください。

## 検証環境

Google Compute Engine 上で、2026-09-29 に検証しました。

- **イメージ：** 標準の `rocky-linux-10`（Rocky 10.2）
- **仮想化：** ネスト仮想化を有効にし、`virt_type=kvm` で動作
- **ビルド用 VM：** n2-standard-4（使用後に削除）
- **node1：** n2-standard-4、ディスク 60 GB で `all-in-one`
- **node2：** n2-standard-2、ディスク 40 GB で `compute-add`
- **SELinux：** permissive

確認できたことは次のとおりです。

- 実際の `dnf install` が完了した
- すべての phase が、スキップなしで完了した
- Keystone、Glance、Placement、Neutron、Nova へのトークン認証付き呼び出しが成功した
- OVN のシャーシが 2 つ登録された
- 両方のノードが、コンピュートサービスとハイパーバイザの一覧で `up` になった
- node1（18 秒）と node2（12 秒）でゲストが ACTIVE になった
- node1 で cloud-init が完了した
- 別々のノード上のゲスト同士が ping で通信でき、そのパケットを Geneve トンネル上で捕捉した
- Horizon に admin でサインインできた
- 両方のノードで、再実行が終了コード 0 で何も再起動しなかった

Horizon は最後に追加しました。
追加した後に node1 を確認し直し、ほかのサービスが引き続き応答すること、ゲストが引き続き ACTIVE になることを確かめました。

## 既知の制約

**含まれないもの**

- **provider NIC の接続。** provider NIC を `br-ex` に**接続しません**。
  自分で NIC を接続するまで、provider ネットワークと Floating IP は物理 LAN に到達しません。
- **その他のサービス。** Cinder（ボリューム）、Swift などの OpenStack サービスは導入しません。
- **noVNC。** コンソールプロキシは導入しません。
- **SELinux ポリシー。** OpenStack 用の SELinux ポリシーは導入せず、ホストを permissive に切り替えます。
- **ファイアウォール。** ホストファイアウォールは設定しません。
  API、RabbitMQ、OVN southbound データベース、memcached は管理ネットワーク上で待ち受けます。
  ノードは信頼できるネットワークに置いてください。
- **パッケージの署名。** RPM には署名がなく、追加するリポジトリは `gpgcheck=0` です。

**未検証のもの**

- **SELinux の enforcing モード**
- **`%check`：** x86_64 の RPM では、パッケージのテストスイートを実行していません。
- **テナントネットワークより外のネットワーク：** 物理 LAN を経由する経路と、ホストの外から Floating IP に到達すること
- **ライブマイグレーション**
- **3 台以上の構成**
- **他の EL10 系ディストリビューション**
- **ホストファイアウォールが有効なホスト**

**サポート外のもの**

- x86_64 以外のアーキテクチャ
