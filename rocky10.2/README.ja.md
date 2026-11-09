# Hagistack for Rocky Linux 10.2

[English](README.md) | 日本語

[← Hagistack の概要](../README.ja.md)

> **OpenStack の RPM の入手方法**
> Rocky Linux には OpenStack が含まれず、EL10 向けの OpenStack 2026.1 はどこからも公開されていません。
> そこで `hagistack` 自身が 2026.1 の RPM を用意します。方法は `--rpm-source` で選ぶ 4 つです
> （「[RPM の入手方法](#rpm-の入手方法)」を参照）。
> 固定された公開リリースのダウンロード（`github`、既定）、**このホスト上でのソースビルド**（`build`）、
> コントローラの RPM の再利用（`bundle`）、手元のリポジトリの利用（`--repo-url`）です。
> 利用者が RPM をビルドしたり DNF リポジトリを手で作ったりする必要はありません。
>
> **2026-11-09 時点：** RPM のリリースはまだ公開していません。そのため既定の `github` は理由を表示して停止します。
> 公開されるまでは `--rpm-source build`（または `--repo-url`）を使ってください。

## 概要

`hagistack` は 1 本の Bash スクリプトです。
リリース版の 2026.1 tarball からビルドした RPM を使い、
Rocky Linux 10.2 に OpenStack 2026.1（Gazpacho）を導入します。対応する構成は 4 つです。

- **`all-in-one`**：コントロールプレーン全体とコンピュートサービスを、1 台のホストにまとめて導入します。
- **`controller`**：コントロールプレーンだけを導入します。ハイパーバイザは入りません。
- **`compute-add --local`**：あとからそのコントローラにハイパーバイザを追加し、all-in-one と同等にします。コントローラの再設定は行いません。
- **`compute-add --controller-ip IP`**：別のホストで実行し、リモートのコンピュートノードを追加します。台数分繰り返します。

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
- **2026.1 の RPM：** 事前準備は不要です。`hagistack` がダウンロード・ビルド・展開します（「[RPM の入手方法](#rpm-の入手方法)」）。
  `--rpm-source build` には追加で約 30 GB のディスク、ビルド入力へのインターネット接続、数時間が必要です。
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

- Rocky Linux 10.2 x86_64 で、コントローラと**同じ RPM セット**を使うこと（`compute-add` が確認し、異なれば停止します）。
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
                         hagistack（各ノードで同じ 1 本のスクリプト）
                         ─────────────────────────────────────
 --rpm-source github ─┐
 --rpm-source build  ─┼─▶ /var/lib/hagistack の検証済み RPM セット ─▶ file:// リポジトリ
 --rpm-source bundle ─┤                                                (priority=1)
 --repo-url URL      ─┘─────────────────────────────────────────▶ あなたのリポジトリ
                                                                       │
                     all-in-one │ controller │ compute-add ◀── dnf install
```

**OpenStack のパッケージは、すべて 2026.1 の RPM セットから入ります。**
そのリポジトリは `priority=1` で登録します。
RDO の OpenStack コンポーネントリポジトリ（`delorean-component-*`）はトランクのスナップショットを含むため、
Hagistack はノードに追加しません。有効になっている場合は警告を出します。

サードパーティの Python ライブラリは RDO の依存ツリーから入り、バージョンは EL10 にあるものになります。
これらは OpenStack の成果物ではありません。`python3-cliff` と `python3-requestsexceptions` は、
2026.1 が固定するのと同じ upstream バージョンを EPEL 10 から使います。

## RPM の入手方法

| `--rpm-source` | 用途 | 動作 |
|---|---|---|
| `github`（既定） | 通常のインストール | `rpm-release.lock` が指すリリースアセットをダウンロードし、そのファイルに固定された SHA-256・サイズ・RPM セット識別子で検証 |
| `build` | ソースからのビルド | このホスト上の使い捨て Rocky 10.2 コンテナで `build-rpms.sh` を実行し、結果を検証 |
| `bundle` | ソースビルドしたコントローラに追加するコンピュートノード | `hagistack rpm-bundle` で作った tarball を、コントローラの RPM セット識別子で検証 |
| `repo-url` | 既存のリポジトリ | 従来どおり `--repo-url` を使う。このモードでは Hagistack は何も検証しない |

共通の規則：

- **勝手に切り替えません。** ダウンロードに失敗してもビルドは始めず、ビルドに失敗してもダウンロードはせず、「最新版」にも切り替えません。
- **使う前に検証します。** 各 RPM が一覧（`RPM-SHA256SUMS`）と一致すること、セット識別子（一覧の SHA-256）が期待値と一致すること、
  リポジトリのメタデータがファイルと一致すること、各 RPM の `rpm -K` が通ることを確認します。
- **再実行では再利用します。** 検証済みセットは再確認したうえで再利用し、二重にダウンロードやビルドはしません。
  検証に通らなくなったキャッシュは削除せず退避し、`github` なら取り直します。
- **1 つのクラウドに 1 つのセット。** 各ノードはセットを記録します。異なるセットでの再実行は何もインストールせずに停止し、
  コンピュートノードはコントローラと異なるセットなら停止します。

**`github` で何を信頼するか。** ダウンロードの横に置かれたチェックサムは、ダウンロードを差し替えられる者なら一緒に差し替えられるため、何も証明しません。
信頼の起点は**この Git チェックアウトの** `rpm-release.lock` です。アセットの SHA-256 とサイズ、中の RPM セット識別子、
ビルド元の `gazpacho.manifest` を固定しています。RPM 自体には GPG 署名はありません。

**`build`：ソースからビルドする**

```sh
sudo ./hagistack all-in-one --rpm-source build   # ほかの設定もあわせて指定
# 先に RPM だけ用意し、あとで再ビルドなしにインストールすることもできます
sudo ./hagistack rpm-prepare --rpm-source build
```

- 別マシンは不要です。ビルドはコンテナ（`quay.io/rockylinux/rockylinux:10.2`、digest で固定）で行うため、
  ビルド依存パッケージや RDO のトランクリポジトリがホストに入ることはありません。`podman` がなければ導入します。
- 数時間かかります。進捗：`/var/lib/hagistack/rpm-build/<id>/out/logs/pass1.log`
- 2 パスで実行します。マニフェストはサービスをライブラリより先に並べているため、ライブラリができた後にサービスを再ビルドします。
- 結果は `/var/lib/hagistack/rpm-build/<id>/` に残ります。`<id>` はビルド入力の識別子で、同じ入力は再ビルドしません。

**`bundle`：コントローラの RPM をコンピュートノードで再利用する**

```sh
# コントローラで
sudo ./hagistack rpm-bundle --output /root/hagistack-rpms.tar
# ファイルをノードにコピーし、ノードで
sudo ./hagistack compute-add --controller-ip 10.0.0.10 \
    --rpm-source bundle --rpm-bundle /root/hagistack-rpms.tar
```

期待する識別子はコントローラの `compute-secrets` ファイルから読むため、コントローラのセットでない bundle は拒否します。

## RPM リポジトリのビルド

通常は自分で実行する必要はありません。`--rpm-source build` がコンテナ内で実行します。
この節は、保守担当者向けと、別マシンでビルドする場合のための `build-rpms.sh` の説明です。

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
- RDO のパッケージング用テキストは**このリポジトリの現在のツリーに同梱しません**（過去のコミットには残っています）。固定した distgit コミットから取得します。
  RDO の master の spec がリリース版 tarball と合わない箇所には、Hagistack が書いたルール（`spec-adapt/`）を適用します。
  適用対象のファイルと結果の SHA-256 は manifest（`SPEC` 行）に固定し、ビルドのたびに検証します（distgit のそれ以外のファイルはコミットで固定）。
  レビュー済みでない入力、すでに適用済みの入力、合わないルールがあればビルドを止め、黙って飛ばすことはありません。
  詳しくは `spec-adapt/RATIONALE.md` を参照してください。
  `spec-templates/` には、PyPI パッケージ用のテンプレートが 1 つ入っています。
- Neutron だけは「リリース版 tarball をそのまま使う」の例外です。
  2026.1 のどのリリースにも入っていない上流の Neutron コミット `83f1d830` と `91abb5e7` の 2 つも適用します。
  これらは、OVN メンテナンスワーカーがデータベースのロックを持たないまま動き続けることがある競合を修正します。
  現在のツリーにある第三者のソースファイルはこの 2 つの patch だけです。Apache-2.0 で、
  ライセンス全文と通知とともに `third-party/neutron/` に置き、SHA-256（`PATCH` 行）で固定しています。
  そのため Neutron の RPM はリリース `2`（`28.0.2-2`）です。
  修正は `tests-neutron-maintenance-lock.py` で確認します。
- PyPI の sdist のうち 5 つ（jQuery、jQuery Migrate、quicksearch、TableSorter、jQuery UI）にはライセンスファイルがありません。
  上流のライセンス本文を `third-party/licenses/` に置き（詳細は同じディレクトリの `NOTICE.md`）、SHA-256（`LICENSE` 行）で固定して、
  それらの RPM に `%license` として入れます。
- `openstack-dashboard` には、ビルド時の `collectstatic` が作る XStatic ライブラリの写しと、それを圧縮したバンドルを入れません
  （spec-adapt のルール `horizon`）。httpd の drop-in が、httpd の起動前に、導入済みの XStatic パッケージから両方を作り直します（以前から同じ動作です）。
  リリース候補を作るスクリプトは、この 2 点をビルド済みの RPM で確認し、`THIRD_PARTY_NOTICES.md` を候補に含めます。

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
`build-rpms.sh --manifest epoxy.manifest` は、`spec-adapt/` に 2026.1 用のルールがあるパッケージでは止まります。
そのルールは 2025.1 の spec には適用できないためです。
`probe-repos.sh` は、公開されている EL10 向け OpenStack リポジトリを読み取り専用で調べ直すツールです。
そのメッセージが参照しているのはこの README の旧版の節で、旧版は Git の履歴にあります。

## 自分のリポジトリを使う（`--repo-url`）

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
| `--rpm-source SRC` | `RPM_SOURCE` | | `github`。`--repo-url` があれば `repo-url`。導入済みホストでは記録済みの方式 |
| `--repo-url URL` | `REPO_URL` | `--rpm-source repo-url` のとき | —（`http(s)://…` または `file:///…`） |
| `--rpm-bundle PATH` | `RPM_BUNDLE` | `--rpm-source bundle` のとき | — |
| `--rpm-set-sha256 HEX` | `RPM_SET_EXPECTED` | | `compute-add` では compute-secrets から読む |
| `--rpm-lock-file PATH` | `RPM_LOCK_FILE` | | `rocky10.2/rpm-release.lock`（ミラーの試験用） |
| `--build-image REF@sha256:…` | `BUILD_IMAGE` | | 固定済みの Rocky 10.2 イメージ |
| `--ext-nic NAME` | `EXT_NIC` | all-in-one、controller | — |
| `--provider-cidr CIDR` | `PROVIDER_CIDR` | all-in-one、controller | — |
| `--provider-gateway IP` | `PROVIDER_GATEWAY` | all-in-one、controller | — |
| `--floating-start IP` | `FLOATING_START` | all-in-one、controller | — |
| `--floating-end IP` | `FLOATING_END` | all-in-one、controller | — |
| `--tenant-cidr CIDR` | `TENANT_CIDR` | | `10.10.10.0/24` |
| `--dns-server IP` | `DNS_SERVER` | | provider のゲートウェイ |
| `--provider-physnet NAME` | `PROVIDER_PHYSNET` | | `physnet1` |
| `--provider-bridge NAME` | `PROVIDER_BRIDGE` | | `br-ex` |
| `--image-name NAME` | `IMAGE_NAME` | | `cirros-0.6.3-x86_64` |
| `--image-url URL` | `IMAGE_URL` | | CirrOS 0.6.3 のダウンロード URL |
| `--image-sha256 HEX` | `IMAGE_SHA256` | URL を変更したら必ず指定 | CirrOS が公開しているダイジェスト |
| `--image-file PATH` | `IMAGE_FILE` | | —（ダウンロードせず、ローカルのファイルを使います） |
| `--controller-ip IP` | `CONTROLLER_IP` | リモートの compute-add | — |
| `--local` | — | | このコントローラにハイパーバイザを追加（compute-add のみ） |
| `--mgmt-ip IP` | `MGMT_IP` | | 自動検出 |
| `--virt-type kvm\|qemu` | `VIRT_TYPE` | | `/dev/kvm` から自動判定 |
| `--region-name NAME` | `REGION_NAME` | | `RegionOne` |

`--provider-physnet` と `--provider-bridge` は、`--help` の一覧には出ませんが使えます。

`hagistack.env` の例です（値は仮のものです）。

```sh
RPM_SOURCE=build
EXT_NIC=eth1
PROVIDER_CIDR=192.0.2.0/24
PROVIDER_GATEWAY=192.0.2.1
FLOATING_START=192.0.2.100
FLOATING_END=192.0.2.200
```

## preflight チェック

```sh
cd hagistack/rocky10.2
sudo ./hagistack all-in-one --check --rpm-source build \
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
- RPM 入手方法の設定と、このホストの記録済みの役割でこのコマンドを実行してよいか
- ディスクとメモリ

最後に、最終的な各設定値とその出どころを表示します。

`--check` では次のことは**確認しません**。インストーラがその段階に達したときに確認します。

- RPM セットをダウンロード・ビルド・展開できるかどうか（RPM 入手の phase で実施）
- `--repo-url` が使えるかどうか（リポジトリの phase で確認）
- `compute-add` の場合、コントローラのポートに到達できるかどうか（コンピュート用 preflight で確認）

## all-in-one のインストール

```sh
sudo ./hagistack all-in-one --rpm-source build   # ほかの設定もあわせて指定
# リリース公開後は次だけで済みます
sudo ./hagistack all-in-one                      # ほかの設定もあわせて指定
```

phase は次の順に実行されます。

1. preflight
2. RPM の入手（ダウンロード・ビルド・展開と検証）
3. リポジトリ
4. SELinux
5. secrets
6. パッケージ
7. MariaDB
8. RabbitMQ
9. memcached
10. Keystone
11. Glance
12. Placement
13. OVS/OVN
14. Neutron
15. Nova
16. nova-compute
17. 初期リソース
18. Horizon

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

## controller だけを導入し、あとでローカルにハイパーバイザを追加する

```sh
sudo ./hagistack controller --rpm-source build   # all-in-one と同じ設定もあわせて指定
```

`controller` は nova-compute 以外の all-in-one の phase をすべて実行します。
Keystone、Glance、Placement、Nova API/scheduler/conductor、OVN 付きの Neutron（コントローラはゲートウェイシャーシ）、Horizon、初期リソースです。
`openstack-nova-compute`、`libvirt`、`qemu-kvm` は入れません。**コンピュートノードができるまでゲストは起動できません**が、それが正常です。

あとで同じホストにハイパーバイザを追加するには：

```sh
sudo ./hagistack compute-add --local
```

コントローラに記録された RPM セット・管理 IP・リージョンを使い、コントローラの phase は再実行しません（資格情報・設定・データはそのまま）。
ハイパーバイザのパッケージを入れ、libvirt と nova-compute を起動し、このホストが `up` になるのを待って cell に登録します。
その後、このホストは `all-in-one` として記録されます。

導入済みホストで実行できるもの：

| 記録済みの役割 | `all-in-one` | `controller` | `compute-add --local` | リモートの `compute-add` |
|---|---|---|---|---|
| controller | 可（ハイパーバイザを追加） | 可（再実行） | 可 | 拒否 |
| all-in-one | 可（再実行） | 拒否 | 可（再実行） | 拒否 |
| compute | 拒否 | 拒否 | 拒否 | 可（再実行） |

役割は `/etc/hagistack/deployment.env` に記録します。Hagistack がサービスを取り除くことはありません。

## コンピュートノードの追加

各手順は、書かれているマシンで実行します。ノードごとに手順 1〜5 を繰り返します。

**1. コントローラで：** コンピュートノードに必要な資格情報をファイルに書き出します。
このコマンドは端末への出力を拒否します。

```sh
(umask 077; sudo ./hagistack compute-secrets > compute-secrets.env)
```

`compute-secrets.env` を作るのは `hagistack` ではなくシェルなので、mode は umask で決まります。
上の `umask 077` によって、自分だけが読めるファイルになります。

このファイルに入るのは、次の 5 つの資格情報と、コントローラの RPM セット識別子（`RPM_SET_SHA256`、秘密情報ではない）だけです。

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

```sh
sudo install -d -m 0700 /etc/hagistack
sudo install -o root -g root -m 0600 /tmp/compute-secrets.env /etc/hagistack/secrets.env
shred -u /tmp/compute-secrets.env
```

**4. 新しいノードで：** `compute-add` を実行します。

```sh
cd hagistack/rocky10.2
# コントローラを公開リリース（github）で導入した場合
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP
# コントローラをソースビルドで導入した場合：再ビルドせずコントローラの RPM を使う
#   （コントローラで：sudo ./hagistack rpm-bundle --output /root/hagistack-rpms.tar）
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP \
    --rpm-source bundle --rpm-bundle /root/hagistack-rpms.tar
# コントローラを --repo-url で導入した場合
sudo ./hagistack compute-add --controller-ip CONTROLLER_MGMT_IP --repo-url URL
```

`compute-add` は資格情報を生成しません。`/etc/hagistack/secrets.env` がない場合や、有効な `RPM_SET_SHA256` を含まない場合は停止します（コントローラでこのバージョンを使って作り直してください）。
ほかの変更より**前に**コントローラのポートへの到達性を確認し、
このノードの RPM セットがコントローラと異なれば、パッケージをインストールする前に停止します。
また、このノードで Nova のデータベース接続設定が有効なまま残っている場合（`nova.conf` 以外に nova-compute が読むファイルも含む）は、nova-compute を起動せずに停止します。

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
sudo ./hagistack all-in-one  [rpm options] [options]
sudo ./hagistack controller  [rpm options] [options]   ハイパーバイザなし
sudo ./hagistack all-in-one  --check [options]         preflight のみ。何も変更しない
sudo ./hagistack compute-add --local                   コントローラで実行。ハイパーバイザを追加
sudo ./hagistack compute-add --controller-ip IP [rpm options] [options]
sudo ./hagistack compute-secrets > FILE                コントローラで実行。端末への出力は拒否
sudo ./hagistack rpm-bundle --output FILE              コントローラで実行。RPM セットを tarball に
sudo ./hagistack rpm-prepare [rpm options]             RPM の用意と検証のみ
sudo ./hagistack discover-hosts                        コントローラで実行。新しいコンピュートホストを登録
sudo ./hagistack status                                役割、RPM セット、phase、SELinux、サービスの状態
./hagistack --help | --version

rpm options: --rpm-source github|build|bundle|repo-url, --repo-url URL,
             --rpm-bundle FILE, --rpm-set-sha256 HEX, --rpm-lock-file PATH,
             --build-image REF@sha256:...
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
| `/etc/hagistack/deployment.env` | このホストの役割、アドレス、RPM セット識別子。秘密情報なし | `0600` |
| `/var/lib/hagistack/state/` | phase の完了マーカーと、SELinux に対して行ったことの記録 | — |
| `/var/lib/hagistack/rpms/` | `github` と `bundle` の検証済み RPM セット | — |
| `/var/lib/hagistack/rpm-build/` | ソースビルドの作業領域と、ビルド入力ごとの検証済み結果 | — |
| `/etc/yum.repos.d/hagistack-*.repo` | Hagistack が追加したリポジトリ | — |
| `/etc/selinux/config` | `SELINUX=permissive` に設定されます | — |
| `./hagistack.env` | あなたの設定。パスワードを書いてはいけません | — |

## トラブルシューティング

- **「no published RPM release is pinned」と出る。**
  このチェックアウトに対応するリリースはまだ公開されていません。`--rpm-source build` を使うか、手元のリポジトリを `--repo-url` で指定してください。
- **ダウンロードや検証に失敗する。**
  何もインストールしていません。Hagistack はビルドへ切り替えません。ネットワークかミラーを直して再実行するか、自分で `--rpm-source build` を選んでください。
- **「Switching the package set of a running cloud is an upgrade」と出る。**
  このホストは別の RPM セットで導入されています。Hagistack はアップグレードを行いません。
- **リポジトリが「does not offer openstack-keystone」と出る（`--repo-url`）。**
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

**2026-11-09（0.2.0-rocky、実装者による受入。独立監査は未実施）：** GCE 上の Rocky 10.2 VM 4 台で、
`--rpm-source build`（ホスト上のコンテナで 195 RPM をビルド）、`controller` の後の `compute-add --local`、
`all-in-one --repo-url`、リモートの `compute-add` 2 台（`--rpm-source bundle` と、模擬リリースサーバに対する `--rpm-source github`）を検証しました。
すべてのハイパーバイザでゲストが起動し、ノード間で疎通しました。再実行は exit 0 で、再起動はありませんでした。
実際の GitHub Release は未公開で、未試験です。
詳細：[acceptance/ROCKY_INSTALLER_COMPLETION_ACCEPTANCE_2026-11-09.md](../acceptance/ROCKY_INSTALLER_COMPLETION_ACCEPTANCE_2026-11-09.md)

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
