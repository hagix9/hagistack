# Hagistack 刷新調査レポート

> **【検証方針 改訂済み・本書に反映済み】**
> 実動作の必須受入は **GCE 最大 2 台**。開発とホストを変更しない検査は **ローカルコンテナ**で行う。
> **Mac／UTM の実動作・arm64・物理 LAN は任意の追加検証**であり、必須受入条件ではない。
> **AWS は調査のみ**（起動・変更・動作確認は行わない）。
> 検証環境の詳細・費用・受入記録様式は `HAGISTACK_VERIFICATION_SCOPE_2026-09-26.md` を参照。
>
> 判定の要点: **Ubuntu 26.04 = 条件付き GO**（パッケージ入手性は確認済み／構築とゲスト起動は未検証）、
> **Rocky 10.2 = NO-GO（今回調査した RPM を用いる OpenStack 2026.1 の直接構築に限る）**。

- 作成日: 2026-09-26
- 対象リポジトリ: `/Volumes/VGX1000 SSD/Codex/Projects/Hagistack` (branch `master`, HEAD `e308abe`, working tree clean)
- 調査範囲: 既存コード実読 + 一次資料調査（読み取りのみ。リポジトリは変更していない）
- 前提: OpenStack 2026.1 Gazpacho / Rocky Linux 10.2 / Ubuntu Server 26.04 LTS
- 除外エンジン: OpenStack-Ansible, Kolla-Ansible, Packstack, DevStack（Hagistack の構築エンジンとして採用しない）

---

## 0. 成立判定（結論先出し）

### Ubuntu Server 26.04 LTS — **条件付き GO**

**条件付き GO とする理由**: 直接構築に必要なパッケージが**ディストリ標準リポジトリだけで入手できることは実地確認済み**。
一方で、**OpenStack を実際に構築して起動させたことも、Nova でゲスト VM を起動させたことも、本調査では行っていない。**
したがって現時点の判定は「**部材が揃っていることの確認**」までであり、**「動作確認済み」ではない**。
**GCE での実機受入（`HAGISTACK_VERIFICATION_SCOPE_2026-09-26.md` §5 区分 A・B）に合格して初めて「動作確認済み」と書く。**

**確認できたこと（すべて実地確認済み・部材の入手性）**

| 確認事項 | 結果 |
|---|---|
| Ubuntu 26.04 LTS のリリース状態 | `resolute` / 2026-04-23 リリース / `Current Stable Release`（Launchpad API 実取得） |
| 同梱 OpenStack バージョン | 2026.1 Gazpacho（Canonical 公式リリースノート） |
| `neutron-server` | `2:28.0.0-0ubuntu1` / component **main** |
| `nova-compute` | `3:33.0.0-0ubuntu3.1` |
| 必須パッケージ 24 種の存在確認 | 全て HTTP 200（下表参照） |
| arm64 対応 | Python 系サービスは `Architecture: all`、`ovn-host` は arm64 ビルドあり |

存在を個別に確認したパッケージ（`https://packages.ubuntu.com/resolute/<pkg>` が 200）:

```
keystone                 glance-api               placement-api
nova-api                 nova-compute             nova-compute-kvm
nova-compute-qemu        nova-conductor           nova-scheduler
nova-novncproxy          nova-spiceproxy          neutron-server
neutron-dhcp-agent       neutron-l3-agent         neutron-metadata-agent
neutron-openvswitch-agent  neutron-linuxbridge-agent
neutron-ovn-agent        neutron-ovn-metadata-agent  neutron-ovn-maintenance-worker
openstack-dashboard      python3-openstackclient  python3-neutron  python3-neutron-lib
ovn-central              ovn-host                 openvswitch-switch
rabbitmq-server          mariadb-server           memcached
libvirt-daemon-system    qemu-system-x86          cloud-image-utils
```

**未確認事項（「条件付き」の中身。実機受入で潰す）**

0. **OpenStack の構築そのものとゲスト VM の起動が未検証**（本調査では構築コマンドを一切実行していない）。
   これが解消されるまで Ubuntu 26.04 を「実証済み GO」とは書かない。
1. 実機での end-to-end 起動確認（AIO 完走 / cirros が ACTIVE / cloud-init のメタデータ取得 / Horizon ログイン）。
2. `neutron-ovn-agent` / `neutron-ovn-maintenance-worker` は **universe**。`universe` 有効化が前提になる。`neutron-ovn-metadata-agent` と `neutron-server` は main。
3. Ubuntu 26.04 の keystone / placement が uwsgi 起動か Apache mod_wsgi 起動か（パッケージのユニット名とデフォルト bind）。
4. Eventlet → native threading 移行（Nova は 2026.1 で experimental）に伴う並行度設定のデフォルト値。
5. `nova-manage cell_v2` の初期化手順が 26.04 パッケージの postinst でどこまで自動化されているか。

### Rocky Linux 10.2 — **NO-GO（今回調査した RPM を用いる OpenStack 2026.1 の直接構築に限定）**

**この NO-GO の適用範囲を限定して書く。**

- **NO-GO と判定する対象**: 「Rocky Linux 10.2 上で、**配布されている RPM パッケージ**を `dnf` で導入して
  OpenStack 2026.1 を直接構築する」という、本調査が対象とした手段。
  この手段については、OpenStack 本体だけでなく **Neutron のデータプレーンである Open vSwitch / OVN すら
  EL10 向けの RPM が配布されていない**ため、**部材が存在せず成立しない**。
- **NO-GO と判定していない対象**: ソースビルド、`pip`/venv 導入、コンテナ利用、自前での RPM ビルド、
  上流ソースからの組み上げなど。**これらは本調査で調べていないため、可否を判断していない。**
  「いかなる方法でも Rocky 10.2 に OpenStack を構築できない」とは主張しない。
- **今回の扱い**: いずれにせよ**今回の実装対象からは外す**。実装・検証は Ubuntu 26.04 に集中する。

**根拠（すべて実地確認済み。以下はすべて「RPM の入手性」についての事実）**

1. **CentOS Stream 10 Cloud SIG に OpenStack が 1 つも無い**
   `https://mirror.stream.centos.org/SIGs/10-stream/cloud/x86_64/` の中身は
   `okd-4.18 / 4.19 / 4.20 / 4.21 / 4.22 / 5.0 / 5.1` のみ。`openstack-*` は **ゼロ**。
   対して 9-stream は `openstack-wallaby` 〜 `openstack-epoxy`(2025.1, 最終更新 2025-05-19) が並ぶ。
   → `dnf install centos-release-openstack-<release>` に相当するものが EL10 には存在しない。

2. **RDO が Epoxy/2025.1 以降 RPM を出していない**
   rdoproject.org の記載: *"As of August 2026 there are no RPM after Epoxy/2025.1, there is an ongoing effort to resume releasing them, please contribute."*
   2025年5月にメンテナ離脱を告知、2026年3月に Epoxy 以降の RPM リリースを停止しコンテナ主体へ方針転換。

3. **RDO trunk の CentOS 10 は master ブランチのみ・untested・かつコアが全滅**
   `https://trunk.rdoproject.org/` に載る CentOS 10 は "master" のみ（stable/2026.1 は無い）。"Latest (untested!) trunk repos" 扱い。
   `https://trunk.rdoproject.org/centos10/status_report.csv`（253 行、最終ビルド 2026-05-31、本日時点で約 4 か月停止）を集計:

   - SUCCESS 201 / **FAILED 51**
   - FAILED の中に **Hagistack 最小構成のほぼ全部**が入っている:
     `openstack-nova`, `openstack-neutron`, `openstack-keystone`, `openstack-glance`,
     `openstack-placement`, `python-django-horizon`, `openstack-cinder`, `openstack-heat`,
     `openstack-ironic`, `ansible-collections-openstack` ほか

   つまり「EL10 向けに未テストの trunk を使う」という妥協をしても、**Nova / Neutron / Keystone / Glance / Placement / Horizon の RPM はそもそもビルドが通っていない**。
   （これは RPM 配布の事実であって、ソースからビルドできるかどうかを示すものではない。）

4. **上流インストールガイドに EL10 の行が無い**
   `https://docs.openstack.org/install-guide/environment-packages-rdo.html` の OS 対応表は
   `CentOS 7/RHEL 7` → `CentOS Stream 8/RHEL 8` → `CentOS Stream 9/RHEL 9` で終わり。EL10 の記載なし。
   コマンド例も `### CentOS Stream 9` / `### RHEL 9` / `### EL9` のみ。

5. **Rocky Linux 10.2 本体に OVS / OVN が無い**
   `BaseOS` / `AppStream` / `CRB` / `extras` / `NFV` を走査した結果:
   - `qemu-kvm-10.1.0-16.el10_2.*` … **あり**
   - `libvirt-daemon-kvm-11.10.0-12.*.el10_2` … **あり**
   - `openvswitch` … **なし**（唯一のヒットは `pcp-pmda-openvswitch`＝Performance Co-Pilot の計測エージェントであって OVS 本体ではない）
   - `ovn` … **なし**
   - Rocky 10 `NFV` リポジトリの実体は `kernel-rt` / `realtime-setup` / `rteval` / `tuned-profiles-nfv` のみ
   - Rocky SIG `https://dl.rockylinux.org/pub/sig/10/cloud/x86_64/` の中身は `cloud-common` のみ（OpenStack ではない）
   - CentOS Stream 10 NFV SIG には `openvswitch-2/`（2026-09-08）があるが、これは c10s 向けであり Rocky 10 のリポジトリ構成には含まれない

6. **EPEL / Fedora にも無い**
   `packages.fedoraproject.org` で `openstack-nova` / `openstack-neutron` / `openstack-keystone` /
   `python3-openstackclient` はいずれも 404（対照として `httpd` / `python3-requests` は 200 なので URL 形式の問題ではない）。

**「Rocky Linux 10 対応」という表記について**
本調査では「Rocky Linux 10 に対応」と書かれた第三者記事（idroot 等）も検索に出たが、
それらは OpenStack **Rocky リリース**（2018年、EOL）との名称混同、もしくは Yoga 世代の EL9 手順の流用であり、
Rocky Linux 10.2 + OpenStack 2026.1 の動作確認の証拠にはならない。採用しない。

**判定を覆す条件（これが揃えば RPM 直接構築を再評価する）**

- CentOS Cloud SIG が `10-stream/cloud/` に `openstack-gazpacho` 等を公開し、Rocky がそれをリビルドする
- RDO が EL10 向け stable ブランチの RPM ビルドを再開し、少なくとも nova/neutron/keystone/glance/placement/horizon が SUCCESS になる
- CentOS NFV SIG または Rocky が EL10 向け `openvswitch` / `ovn` を配布する

**調べていない手段について**: 上記とは別に、ソースビルドや自前パッケージングで成立させる道は残っている可能性がある。
本調査はその可否を評価していない。評価するなら、まず **EL10 上での OVS / OVN の入手または自前ビルド**が
成立するかを最初に確かめるのが筋（OpenStack 本体より先にここで詰まるため）。

### 補足判定

| 組み合わせ | 判定 |
|---|---|
| Ubuntu 26.04 + OpenStack 2026.1（ディストリ標準パッケージ） | **条件付き GO** — 部材の入手性は確認済み。構築とゲスト起動は未検証。GCE 受入で確定する |
| Rocky Linux 10.2 + OpenStack 2026.1（**配布 RPM による直接構築**） | **NO-GO** — RPM が存在しない（OVS/OVN も無い） |
| Rocky Linux 9.x + OpenStack 2025.1 Epoxy（CentOS Stream 9 Cloud SIG 経由） | **未確認（成立の見込みはある）** — 9-stream Cloud SIG に `openstack-epoxy` が実在する。ただし Rocky 9 での動作は本調査で未検証。RPM を残したい場合の退避先候補 |
| Rocky 10.2 にソースビルド / pip / venv / 自前 RPM で導入 | **未調査（判定しない）** — 本調査の対象外。可否を主張しない。今回の実装対象からは外す |

---

## 1. 現状把握

### 1.1 ディレクトリ構成

```
.
├── .gitmodules            (0 バイト・空)
├── README.rst             (0 バイト・空)
├── centos6.2/             hagistack_controller.sh, hagistack_compute.sh, README.md
├── centos6.3/             同上（6.2 とほぼ同一。中身の記述は "CentOS6.2" のまま）
├── make_img/              make_img_centos6.4.sh
├── ubuntu12.04/           controller, controller_grizzly, controller_havana_neutron,
│                          compute, compute_grizzly, compute_havana
├── ubuntu12.04_git/       controller, compute
├── ubuntu12.10/           controller, compute
├── ubuntu13.04/           controller, controller_quantum, compute, compute_quantum
├── ubuntu13.04_git/       同上
├── ubuntu13.10/           hagistack_controller_neutron.sh, hagistack_compute_neutron.sh, README.md
├── rocky10.2/             空ディレクトリ（Git 未追跡）
└── ubuntu26.04/           空ディレクトリ（Git 未追跡）
```

- 追跡ファイル 35、シェル 22 本、合計 11,249 行。
- `rocky10.2/` と `ubuntu26.04/` は `git ls-files` に出てこない＝**まだ何も無い placeholder**。
- 最新コミット `e308abe ansible mv hagistack2_ubuntu repo`。実質的な最終世代は `ubuntu13.10`（OpenStack Havana / 2013年）。

### 1.2 実際に読んだ主なファイル

| ファイル | 行数 | 内容 |
|---|---|---|
| `ubuntu13.10/hagistack_controller_neutron.sh` | 687 | 最新世代のオールインワン相当。Havana + Neutron(OVS/GRE) |
| `ubuntu13.10/hagistack_compute_neutron.sh` | 265 | コンピュート追加 |
| `ubuntu13.10/README.md` | 53 | 利用手順 |
| `centos6.3/hagistack_controller.sh` | 531 | RPM 系の系譜（Essex） |
| `centos6.3/README.md` | 53 | 同上 |
| `ubuntu13.04_git/hagistack_controller_quantum.sh` | 1228 | 最大のシェル（Git 版 Quantum） |

### 1.3 旧シェルが実現していた機能（整理）

`ubuntu13.10/hagistack_controller_neutron.sh` を基準にすると、1 本のシェルで以下を通していた。
設計意図としてはこれが「Hagistack が実現したかったこと」であり、刷新後も要求として残る。

1. 冒頭に環境変数ブロック（IP / ホスト名 / 各種パスワード / テナント定義 / 外部 IP プール）
2. `stack.env` があれば読み込んで上書き（`if [ -f stack.env ] ; then . ./stack.env ; fi`）
3. OS 更新、NTP、`vlan` / `bridge-utils`、`sysctl`（ip_forward / IPv6 無効）
4. MySQL 導入 → サービスごとの DB / ユーザー / GRANT 作成
5. RabbitMQ 導入 → vhost `/nova`、ユーザー `nova`、`guest` 削除
6. Keystone → Glance → OVS → Neutron → Nova → Horizon → Cinder → KVM/libvirt の順に導入・設定・起動
7. テナント、ユーザー、内部ネットワーク、ルーター、外部ネットワーク、Floating IP プールの作成
8. セキュリティグループ（ICMP / TCP22）、キーペア、フレーバー調整
9. ゲストイメージ（CoreOS）の取得と Glance 登録
10. `/etc/bash.bashrc` に `keystonerc` の読み込みを追記

コンピュート側は 3 / OVS(br-int) / `neutron-plugin-openvswitch-agent` / `nova-compute` / KVM のみ。

### 1.4 現在は使えない設定・コマンド・パッケージ名（具体箇所つき）

**(A) サービス／アーキテクチャそのものが消滅したもの**

| 箇所 | 問題 |
|---|---|
| `ubuntu13.10/hagistack_controller_neutron.sh`（Keystone 設定部） | `OS_AUTH_URL=http://.../v2.0/`、`auth_port = 35357`。**Identity API v2.0 は削除済み、35357 ポートも廃止**。現在は v3 単一・5000 のみ |
| 同（Glance 設定部） | `/etc/glance/glance-registry.conf` を sed。**glance-registry はサービスごと削除済み** |
| 同（Nova 設定部） | Placement への参照が皆無。**Placement は Nova から分離した必須サービス**で、独立 DB・独立エンドポイントが要る |
| 同（Nova 設定部） | `nova-manage db sync` のみで **cells v2 の初期化（`map_cell0` / `create_cell` / `discover_hosts`）が無い**。現在は必須 |
| 同（Nova サービス起動ループ） | `for proc in api cert console consoleauth scheduler compute novncproxy conductor`。**`nova-cert` / `nova-console` / `nova-consoleauth` は全て削除済み** |
| `ubuntu12.04/*`, `centos6.*` 系 | `nova-network` 前提の世代が残存。**nova-network は削除済み** |
| 同（Neutron 設定部） | `core_plugin = neutron.plugins.openvswitch.ovs_neutron_plugin.OVSNeutronPluginV2`。**このプラグインパスは存在しない**（現在は `ml2` + mechanism driver） |
| 同（Neutron 設定部） | `/etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini`。**現在は `/etc/neutron/plugins/ml2/ml2_conf.ini`** |
| 同（Neutron 設定部） | `[DATABASE]` / `[OVS]` / `[SECURITYGROUP]` の大文字セクション（`compute_neutron.sh` 側）。現在は小文字 |
| 同（Neutron 設定部） | LBaaS (`neutron-lbaas-agent`) / VPNaaS (`neutron-plugin-vpn-agent`) / FWaaS。**いずれも Neutron 本体から退役**。`service_plugins` の指定値も無効 |
| 同（Nova 設定部） | `libvirt_type` / `libvirt_vif_driver` / `libvirt_use_virtio_for_bridges` / `sql_connection` / `rabbit_host` / `nova_url` / `novnc_enabled` / `vncserver_listen` / `glance_api_servers` / `neutron_admin_*`。**全て旧フラット形式**。現在は `[libvirt] virt_type=`, `[database] connection=`, `[DEFAULT] transport_url=`, `[glance] api_servers=`, `[neutron] auth_url/username/password`, `[vnc] server_listen=` 等のセクション形式 |
| 同（Nova 設定部） | `use_deprecated_auth=false`、`osapi_volume_listen_port=5900`（VNC のポートと衝突する誤設定）、`scheduler_driver=`。いずれも無効 |
| 同（CLI） | `keystone tenant-create` / `keystone user-create` / `nova secgroup-add-rule` / `nova keypair-add` / `nova flavor-create` / `glance image-create --is-public` / `neutron net-create` / `neutron subnet-create` / `neutron router-create` / `neutron l3-agent-router-add`。**`keystone` / `nova` / `neutron` / `glance` CLI は全廃、`openstack` CLI に統合**。`tenant` は `project` に改称 |
| 同（起動制御） | `sudo stop keystone` / `sudo start glance-api` / `/etc/init/libvirt-bin.conf`。**Upstart。Ubuntu 26.04 は systemd** |
| 同（パッケージ名） | `libvirt-bin`（現 `libvirt-daemon-system`）、`openvswitch-datapath-dkms`（不要・廃止）、`python-mysqldb`（Python 2）、`neutron-plugin-openvswitch-agent`（現 `neutron-openvswitch-agent`）、`nova-doc`、`sheepdog` |
| 同（MySQL debconf） | `mysql-server-5.5 mysql-server/root_password`。バージョン固定の debconf キー。26.04 には無い |
| 同（Keystone 初期化） | `wget https://raw.github.com/mseknibilel/OpenStack-Grizzly-Install-Guide/...` を取得して `sed` で書き換えて実行。**外部の第三者 Grizzly 用スクリプトへの実行時依存**。URL も現存しない（`raw.github.com` ドメイン自体が旧表記） |
| 同（Glance 初期化） | `wget https://raw.github.com/openstack/glance/master/etc/schema-image.json` を `/etc/glance` へ。同上 |
| 同（イメージ） | `http://storage.core-os.net/coreos/...` から CoreOS イメージ取得。**CoreOS は終息、URL 消滅** |
| `centos6.*/hagistack_controller.sh` | `rpm -i http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-7.noarch.rpm`、`service`/`chkconfig`、`qpidd`、`keystone.catalog.backends.templated.TemplatedCatalog`。全世代遅れ |

**(B) 危険な処理（刷新時に必ず排除する）**

| 箇所 | 危険性 |
|---|---|
| `ubuntu13.10/hagistack_controller_neutron.sh` 冒頭 | `MYSQL_PASS=nova` / `RABBIT_PASS=password` / `MYSQL_PASS_*=password` / `ADMIN_PASSWORD=secrete` / `SERVICE_PASSWORD=secrete` / `TENANT_ADMIN_PASS=admin01` / `metadata_proxy_shared_secret=stack`。**固定パスワードが Git にコミットされている**。今回の刷新方針に真っ向から反する |
| 同（DB 作成部） | `drop database if exists keystone;` を keystone/glance/ovs_neutron/cinder/nova の 5 つに対して無条件実行。**再実行すると既存クラウドのデータを全消去する**。冪等ではなく破壊的 |
| 同（ログ削除） | `sudo \rm -rf /var/log/glance/*`、`/var/log/neutron/*`、`/var/log/nova/*`、`/var/log/cinder/*`。監査証跡を消す |
| 同（Keystone 初期化） | `sudo \rm -rf /usr/local/src/*keystone_basic.sh*` のようにワイルドカード付き `rm -rf` を `sudo` で実行 |
| 同（AppArmor） | `apparmor_parser -R` で libvirtd プロファイルを**無効化**。MAC を落としている |
| 同（libvirt） | `listen_tcp = 1` + `auth_tcp = "none"` で **libvirt を認証なしで TCP 公開**。ライブマイグレーション用途だが無認証は重大 |
| 同（Nova） | `firewall_driver=nova.virt.firewall.NoopFirewallDriver` |
| 同（MySQL） | `sed -i 's#127.0.0.1#0.0.0.0#g' /etc/mysql/my.cnf` で **MySQL を全 IF に公開** |
| 同（sysctl） | `/etc/sysctl.conf` に `tee -a`。**実行のたびに追記され重複が増える**（非冪等） |
| 同（bashrc） | `/etc/bash.bashrc` に `. /home/$STACK_USER/keystonerc` を `tee -a`。同じく重複追記。全ユーザーのシェルに admin 資格情報を注入 |
| 同（libvirt qemu.conf） | `cgroup_device_acl` を `tee -a` で追記。重複すると libvirtd が起動しなくなる |
| 同（sed 群） | `sed -i "s#127.0.0.1#$HOST#"` / `s#localhost#$HOST#` を設定ファイル全体へ無差別適用。コメント行や無関係な項目まで書き換わる |
| 全シェル共通 | `set -euo pipefail` が無い。**どこかが失敗しても最後まで走り切り、半端な状態で「完了」する** |
| 全シェル共通 | 冪等性の考慮が皆無。2 回目の実行は DB 全削除 + 設定重複でほぼ確実に壊れる |
| `ubuntu13.10/hagistack_compute_neutron.sh` | `for proc in proc in compute` … **タイプミスがそのまま残っている**（`proc` が 2 回）。レビューが効いていなかった証拠 |
| `centos6.*` | `setenforce 0` + `SELINUX=disabled` で SELinux 全無効化 |

### 1.5 総括

旧 Hagistack は「1 本の Bash で通す」という思想自体は妥当だが、
2013 年の OpenStack Havana に密結合しており、**設定キー・CLI・サービス構成・起動システムのすべてが現行と非互換**。
移植ではなく**新規に書き直す**のが正しい。ただし
「冒頭の環境変数ブロック + `stack.env` による上書き」という利用者インターフェースは良い設計であり、刷新後も継承する価値がある。

---

## 2. 確認した一次資料と、そこから確認できる事実

| # | URL | 確認できた事実 |
|---|---|---|
| 1 | https://releases.openstack.org/gazpacho/schedule.html | OpenStack 2026.1 Gazpacho の最終リリースは **2026-04-01**。サイクルは 2025-10-02 〜 2026-04-01（26 週） |
| 2 | https://github.com/ubuntu/ubuntu-release-notes/issues/56 | Ubuntu 26.04 LTS は **OpenStack 2026.1 Gazpacho** を同梱。Keystone/Neutron/Nova/Glance/Placement/Horizon/Swift/Cinder 等を含む。Gazpacho は SLURP（2025.1 Epoxy から直接アップグレード可）。Nova は Eventlet→native threading が experimental。ML2/OVN に OVN BGP 統合、外部ポートの N/S ルーティング対応 |
| 3 | https://api.launchpad.net/1.0/ubuntu/series | Ubuntu 26.04 = `resolute`、**2026-04-23 リリース**、status `Current Stable Release` |
| 4 | https://packages.ubuntu.com/resolute/neutron-server | `2:28.0.0-0ubuntu1`、component **main** |
| 5 | https://packages.ubuntu.com/search?keywords=nova-compute&suite=all | resolute に `3:33.0.0-0ubuntu3.1`。noble は `3:29.2.0`、questing は `3:32.0.0` |
| 6 | https://packages.ubuntu.com/resolute/{各パッケージ} | 上記 §0 の 30 パッケージすべて存在（HTTP 200） |
| 7 | https://mirror.stream.centos.org/SIGs/10-stream/cloud/x86_64/ | **`openstack-*` が 1 つも無い**。`okd-4.18`〜`okd-5.1` のみ |
| 8 | https://mirror.stream.centos.org/SIGs/9-stream/cloud/x86_64/ | `openstack-wallaby` 〜 `openstack-epoxy`(2025-05-19) が存在。**Epoxy/2025.1 が最後** |
| 9 | https://www.rdoproject.org/ | *"As of August 2026 there are no RPM after Epoxy/2025.1, there is an ongoing effort to resume releasing them, please contribute."* 2026年3月に Epoxy 以降の RPM リリースを停止、コンテナ主体へ方針転換 |
| 10 | https://trunk.rdoproject.org/ | CentOS 10 は **master ブランチのみ**。stable/2026.1 は無い。"Latest (untested!) trunk repos" 表記 |
| 11 | https://trunk.rdoproject.org/centos10/status_report.csv | 253 行。**SUCCESS 201 / FAILED 51**。最終ビルド **2026-05-31**。FAILED に `openstack-nova` `openstack-neutron` `openstack-keystone` `openstack-glance` `openstack-placement` `python-django-horizon` を含む |
| 12 | https://docs.openstack.org/install-guide/environment-packages-rdo.html | OS 対応表の最新行が **CentOS Stream 9 / RHEL 9**（Xena 以降）。**EL10 の行は存在しない**。Maintained は 2023.2/2024.1/2024.2 まで |
| 13 | https://docs.openstack.org/install-guide/environment-packages-ubuntu.html | Ubuntu は各 Ubuntu リリースごとに OpenStack を同梱。中間リリースの OpenStack は Cloud Archive で LTS に提供 |
| 14 | https://dl.rockylinux.org/pub/rocky/10/ | リポジトリは `BaseOS` `AppStream` `CRB` `devel` `extras` `HighAvailability` `NFV` `plus` `RT` `SAP` `SAPHANA` `security`。**OpenStack 用リポジトリは無い** |
| 15 | https://dl.rockylinux.org/pub/rocky/10/AppStream/x86_64/os/Packages/ | `qemu-kvm-10.1.0-16.el10_2.*` / `libvirt-daemon-kvm-11.10.0-12.*.el10_2` は存在。**`openvswitch` 本体・`ovn` は存在しない**（ヒットは `pcp-pmda-openvswitch` のみ） |
| 16 | https://dl.rockylinux.org/pub/rocky/10/NFV/x86_64/os/Packages/ | 実体は `kernel-rt` / `realtime-setup` / `rteval` / `tuned-profiles-nfv*` のみ。OVS/OVN 無し |
| 17 | https://dl.rockylinux.org/pub/sig/10/cloud/x86_64/ | `cloud-common` のみ。OpenStack 無し |
| 18 | https://mirror.stream.centos.org/SIGs/10-stream/nfv/x86_64/ | `openvswitch-2/`（2026-09-08）が存在。**c10s には OVS があるが Rocky 10 には無い** |
| 19 | https://packages.fedoraproject.org/pkgs/{openstack-nova,openstack-neutron,openstack-keystone,python3-openstackclient}/ | いずれも **404**（対照 `httpd`/`python3-requests` は 200） |
| 20 | https://docs.cloud.google.com/compute/docs/instances/nested-virtualization/overview | ネスト仮想化 **非対応**: E2 VM、メモリ最適化 VM、**Arm プロセッサ搭載 VM**、**AMD 搭載 VM（N4D のみ例外的に対応）**。L1 のハイパーバイザは **Linux KVM のみ**（Hyper-V 不可）。CPU バウンドで 10% 以上、I/O バウンドでそれ以上の性能低下 |
| 21 | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html | **仮想（非ベアメタル）EC2 でネスト仮想化が可能**。対応タイプ: 汎用 `M7i / M7i-flex / M8i / M8id / M8i-flex`、コンピュート最適化 `C7i / C7i-flex / C8i / C8id / C8i-flex`、メモリ最適化 `R7i / R7iz / R8i / R8id / R8i-flex / X8i`、ストレージ最適化 `I7i / I7ie`。L1 ハイパーバイザは **KVM と Hyper-V**。有効化は `--cpu-options "NestedVirtualization=enabled"`（既存インスタンスは停止後 `modify-instance-cpu-options`）。**追加料金なし**。Nitro が Intel VT-x をインスタンスへ引き渡す。性能要件が厳しい場合はベアメタルを推奨 |
| 22 | https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual | **2026-02-16 発表**。当初 C8i / M8i / R8i、全商用リージョン |
| 23 | https://docs.cloud.google.com/vpc/docs/vpc | *"VPC networks do not support broadcast or multicast addresses within the network."* |
| 24 | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html ほか AWS 公式 | ENI は **プロミスキャスモード非対応**。Nitro がソース/宛先 MAC を ENI 登録内容と照合。`source/dest check` 無効化は IP のチェックのみを外し、**MAC のチェックは外れない** |
| 25 | https://developer.apple.com/documentation/virtualization （macOS 15 Sequoia） | Virtualization.framework が **M3 以降でネスト仮想化に対応**（`isNestedVirtualizationSupported` / `isNestedVirtualizationEnabled`）。M2 以前は非対応。UTM 4.6+ は M3 + macOS 15 で Linux VM のネスト仮想化を既定で有効化 |
| 26 | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/region_index.json | AWS 公式 Price List Bulk API。**publicationDate 2026-09-25T17:45:21Z** |
| 27 | https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSDataTransfer/current/region_index.json | **publicationDate 2026-09-16T13:22:08Z** |
| 28 | https://docs.rockylinux.org/10/release_notes/10_2/ ほか | Rocky Linux 10.2 は **2026-05-28** リリース |

**取得できなかった一次資料**

- **GCE の料金**: Cloud Billing Catalog API は API キー必須で 403（`"Method doesn't allow unregistered callers"`）。
  `https://cloud.google.com/compute/vm-instance-pricing` は JS レンダリングで HTML 内に価格が 1 件も含まれない（`$0.` の出現数 0）。
  → **GCE の金額は本レポートに記載しない**（§7 に見積もりに必要な条件のみ記載）。

---

## 3. 最小サービス構成

前提: Neutron のバックエンドは **ML2/OVN** を第一候補とする。理由は
(a) 2026.1 で OVN が主力であり Ubuntu もパッケージを揃えている、
(b) `neutron-l3-agent` / `neutron-dhcp-agent` / `neutron-metadata-agent` の 3 デーモンが不要になり **デーモン数と設定ファイル数が減る**（＝「単純な Bash」という方針に合う）、
(c) compute-add 側が `ovn-controller` + `neutron-ovn-metadata-agent` + `nova-compute` だけで済む。

ML2/OVS も Ubuntu 26.04 にパッケージは存在する（`neutron-openvswitch-agent` 等）ので代替は可能だが、エージェント数が増える。

### 3.1 all-in-one（1 台にコントロール + コンピュート）

| 層 | サービス | Ubuntu 26.04 パッケージ | 主な設定ファイル | 備考 |
|---|---|---|---|---|
| 基盤 | データベース | `mariadb-server` | `/etc/mysql/mariadb.conf.d/` | サービスごとに DB + ユーザー |
| 基盤 | メッセージキュー | `rabbitmq-server` | `rabbitmqctl` で設定 | vhost `/`、専用ユーザー |
| 基盤 | キャッシュ | `memcached` | `/etc/memcached.conf` | Keystone トークン / Horizon セッション |
| 基盤 | 時刻同期 | `chrony`（systemd-timesyncd でも可） | `/etc/chrony/chrony.conf` | 複数ノード時は必須 |
| 認証 | Keystone | `keystone` | `/etc/keystone/keystone.conf` | **Identity API v3 のみ**。`keystone-manage db_sync` → `bootstrap` |
| イメージ | Glance | `glance-api` | `/etc/glance/glance-api.conf` | registry は無い。`glance-manage db_sync` |
| 配置 | **Placement** | `placement-api` | `/etc/placement/placement.conf` | **独立 DB・独立エンドポイント。省略不可** |
| コンピュート | Nova API 群 | `nova-api` `nova-conductor` `nova-scheduler` `nova-novncproxy` | `/etc/nova/nova.conf` | `nova-manage api_db sync` → `cell_v2 map_cell0` → `cell_v2 create_cell` → `db sync` |
| コンピュート | Nova compute | `nova-compute` `nova-compute-kvm`（または `nova-compute-qemu`） | `/etc/nova/nova.conf` `/etc/nova/nova-compute.conf` | `[libvirt] virt_type=kvm` または `qemu` |
| コンピュート | 仮想化基盤 | `libvirt-daemon-system` `qemu-system-x86`（arm64 なら `qemu-system-arm`） | `/etc/libvirt/` | |
| ネットワーク | Neutron server | `neutron-server` | `/etc/neutron/neutron.conf` `/etc/neutron/plugins/ml2/ml2_conf.ini` | `core_plugin = ml2`, `mechanism_drivers = ovn` |
| ネットワーク | OVN 制御 | `ovn-central` | OVSDB (`ovn-nbctl` / `ovn-sbctl`) | Northbound / Southbound DB + northd |
| ネットワーク | OVN ホスト | `ovn-host` `openvswitch-switch` | `ovs-vsctl set open_vswitch . external_ids:...` | `ovn-controller` |
| ネットワーク | メタデータ | `neutron-ovn-metadata-agent` | `/etc/neutron/neutron_ovn_metadata_agent.ini` | ゲストの cloud-init に必須 |
| 画面 | Horizon | `openstack-dashboard` | `/etc/openstack-dashboard/local_settings.py` | Apache 経由 |
| 運用 | CLI | `python3-openstackclient` | `~/.config/openstack/clouds.yaml` または `openrc` | |

**起動順（依存関係の順）**

```
1. chrony                                     時刻
2. mariadb-server                             DB 起動 → 各サービス用 DB/ユーザー作成
3. rabbitmq-server                            vhost/ユーザー作成
4. memcached
5. keystone       db_sync → bootstrap         → 以降の service/endpoint 登録が可能に
6. glance         db_sync → 起動              → Keystone に service/endpoint 登録
7. placement      db_sync → 起動              → 登録（Nova より先。Nova が問い合わせる）
8. openvswitch-switch → ovn-central → ovn-host(ovn-controller)
9. neutron-server db_sync(ml2) → 起動 → neutron-ovn-metadata-agent
10. nova: api_db sync → map_cell0 → create_cell → db sync → nova-api/conductor/scheduler/novncproxy
11. nova-compute 起動 → 【重要】nova-manage cell_v2 discover_hosts
12. horizon (apache2 reload)
13. 初期リソース: flavor / image(cirros) / provider network / tenant network / router / secgroup / keypair
```

**構築後の疎通確認**

```
openstack --version / openstack token issue         認証
openstack endpoint list                             カタログ（5000 のみ。35357 は無い）
openstack service list
openstack hypervisor list                           compute が Up か
openstack compute service list                      nova-* が up か
openstack network agent list                        OVN Controller / Metadata が Alive か
openstack resource provider list                    Placement が compute を認識しているか
openstack image list                                Glance
openstack network list / subnet list / router list
openstack server create --flavor m1.tiny --image cirros --network <tenant-net> demo1
openstack server list                               ACTIVE になるか
openstack console log show demo1                    cloud-init がメタデータを取れたか
openstack floating ip create <provider-net> ; openstack server add floating ip demo1 <fip>
ping <fip> ; ssh cirros@<fip>                       ゲストの外部通信（§4 の最終確認）
```

### 3.2 compute-add（既存コントロールノードへコンピュート追加）

| 層 | サービス | パッケージ | 設定ファイル |
|---|---|---|---|
| 基盤 | 時刻同期 | `chrony` | `/etc/chrony/chrony.conf` |
| コンピュート | Nova compute | `nova-compute` `nova-compute-kvm` | `/etc/nova/nova.conf` |
| コンピュート | 仮想化基盤 | `libvirt-daemon-system` `qemu-system-x86` | `/etc/libvirt/` |
| ネットワーク | OVS + OVN ホスト | `openvswitch-switch` `ovn-host` | `ovs-vsctl` の `external_ids` |
| ネットワーク | メタデータ | `neutron-ovn-metadata-agent` | `/etc/neutron/neutron_ovn_metadata_agent.ini` |

**ノード間通信（コンピュート → コントローラ）**

| 宛先 | ポート | 用途 |
|---|---|---|
| MariaDB | TCP 3306 | ※ OVN 構成では nova-compute は DB 直結しない設計が基本。`[api_database]`/`[database]` を compute に書かない |
| RabbitMQ | TCP 5672 | Nova / Neutron の RPC。**必須** |
| Keystone | TCP 5000 | 認証。**必須** |
| Glance API | TCP 9292 | イメージ取得。**必須** |
| Placement | TCP 8778 | リソース報告。**必須** |
| Nova API | TCP 8774 | |
| Neutron API | TCP 9696 | |
| **OVN Southbound DB** | **TCP 6642** | `ovn-controller` が接続。**必須** |
| OVN Northbound DB | TCP 6641 | 通常コントローラ内部のみ |
| Geneve トンネル | **UDP 6081** | コンピュート↔コントローラ／コンピュート間。**必須** |
| noVNC proxy | TCP 6080 | コンソール（コントローラ側で受ける） |
| libvirt ライブマイグレーション | TCP 16509 / 49152-49215 | **初期スコープ外**（旧シェルの無認証 TCP 公開は再現しない） |

**起動順**

```
1. chrony（コントローラと時刻が合っていること。ズレると agent が Alive にならない）
2. /etc/hosts またはDNS でコントローラ名を解決可能に
3. openvswitch-switch 起動
4. ovs-vsctl set open_vswitch . external_ids:ovn-remote=tcp:<ctrl>:6642 \
                                external_ids:ovn-encap-type=geneve \
                                external_ids:ovn-encap-ip=<このノードの管理IP>
   → ovn-controller 起動
5. neutron-ovn-metadata-agent 起動
6. libvirtd 起動
7. nova-compute 起動
8. 【コントローラ側で実行】 nova-manage cell_v2 discover_hosts --verbose
   ← これを忘れると追加ノードにインスタンスが載らない。compute-add の最頻出の失敗点
```

**疎通確認**

```
【compute 側】 systemctl is-active openvswitch-switch ovn-controller nova-compute
               ovs-vsctl show                          （br-int があるか）
【ctrl 側】    openstack compute service list --service nova-compute   （新ノードが up）
               openstack network agent list            （新ノードの OVN Controller が Alive）
               openstack resource provider list        （新ノードの RP が出来ているか）
               openstack hypervisor list
               openstack server create ... --availability-zone nova:<新ノード名>
                                                       （新ノード指定で起動できるか）
```

### 3.3 初回実行と再実行（冪等性）

旧シェルの最大の欠陥は `drop database if exists` と `tee -a` による非冪等性だった。刷新では以下を原則とする。

| 対象 | 方針 |
|---|---|
| パッケージ導入 | `apt-get install -y` はもともと冪等。そのままでよい |
| DB 作成 | `CREATE DATABASE IF NOT EXISTS` / `CREATE USER IF NOT EXISTS` / `GRANT`。**`DROP DATABASE` は一切書かない** |
| `db_sync` | 各サービスの db_sync はマイグレーションなので再実行安全 |
| 設定ファイル | `tee -a` を廃止し、`crudini --set` 相当（または自作の `ini_set` 関数）で**キー単位の冪等更新**にする。`sed -i` の無差別置換も廃止 |
| Keystone 初期化 | `keystone-manage bootstrap` は冪等。`openstack service create` / `endpoint create` は既存チェックを挟む（`openstack service show <name> >/dev/null 2>&1 \|\| openstack service create ...`） |
| OVS/OVN | `ovs-vsctl --may-exist add-br` / `--if-exists` を使う（旧シェルも `--may-exist` は使えていた） |
| sysctl | `/etc/sysctl.d/99-hagistack.conf` に**ファイルごと上書き**（`tee -a` しない） |
| ネットワーク/フレーバー/イメージ | `openstack X show <name> >/dev/null 2>&1 \|\| openstack X create ...` |
| パスワード | 初回に生成し `/etc/hagistack/secrets.env`（`chmod 600`）へ保存、2 回目以降はそれを読む。**生成物は Git 管理外** |
| 全体 | 先頭で `set -euo pipefail`。各フェーズを関数化し、`/var/lib/hagistack/state/<phase>.done` のマーカーで再実行時にスキップ可能にする（`--force` で無視） |
| 破壊的操作 | `--wipe` のような明示フラグを付けたときだけ DB 削除を許す。既定では絶対にしない |

### 3.4 ディストリ差分（参考）

今回 Rocky は NO-GO のため実装対象外だが、将来 EL 系が復活した場合に備えて差分を記録しておく。

| 項目 | Ubuntu 26.04 | EL 系（仮に復活した場合） |
|---|---|---|
| パッケージ管理 | `apt-get` | `dnf` |
| リポジトリ有効化 | 標準で同梱（追加作業なし） | `dnf install centos-release-openstack-<release>` + CRB 有効化 |
| パッケージ名 | `nova-api`, `neutron-server`, `openstack-dashboard` | `openstack-nova-api`, `openstack-neutron`, `openstack-dashboard` |
| サービス単位 | 機能ごとに別パッケージ・別ユニット | 同上だが `openstack-` 接頭辞 |
| DB | `mariadb-server` | `mariadb-server` |
| 設定ディレクトリ | `/etc/nova`, `/etc/neutron` … | 同じ |
| WSGI 実行 | uwsgi / Apache（要確認） | 従来は `httpd` + mod_wsgi が主流 |
| MAC | AppArmor | SELinux（`openstack-selinux` が必要） |
| ファイアウォール | `ufw`（既定 inactive） | `firewalld`（既定 active。要開放設定） |
| OVS/OVN | `openvswitch-switch`, `ovn-central`, `ovn-host` | c9s は NFV SIG、**EL10 は現時点で提供なし** |

---

## 4. ネットワーク

### 4.1 構成比較

| 構成 | 管理 LAN | 外部/プロバイダー LAN | 成立性 | 主な制約 |
|---|---|---|---|---|
| **A. 1 NIC** | eth0（IP あり） | eth0 と共用 | 成立するが注意が要る | ホスト IP を OVS ブリッジ `br-ex` 側へ移す必要がある。**SSH 中に切断するリスク**。Netplan で `br-ex` に IP を持たせ eth0 を無 IP でスレーブ化する手順を、再起動耐性込みで組む必要あり |
| **B. 2 NIC（推奨）** | eth0（IP あり。API/RPC/Geneve） | eth1（**IP を持たせない**。`br-ex` にスレーブ化） | 最も素直に成立 | eth1 が接続される L2 セグメントに、Floating IP に使える空き IP レンジとゲートウェイが必要 |
| **C. 複数ノード** | 各ノード eth0（同一管理セグメント） | コントローラのみ eth1 → `br-ex` | 成立 | Geneve(UDP 6081) が管理 LAN を通ればよい。**コンピュートノードに外部 NIC は不要**（N/S トラフィックはコントローラの gateway chassis 経由） |

### 4.2 Neutron provider network に必要なもの

| 要素 | 要件 |
|---|---|
| NIC | プロバイダー用に 1 本（構成 A なら管理と共用）。**L2 で外部セグメントに直結していること** |
| ブリッジ | OVS ブリッジ（例 `br-ex`）を作り、`ovs-vsctl add-port br-ex eth1` で NIC を収容 |
| マッピング | `ovs-vsctl set open_vswitch . external_ids:ovn-bridge-mappings=physnet1:br-ex`（OVN の場合）／ ML2/OVS なら `ml2_conf.ini` の `[ovs] bridge_mappings = physnet1:br-ex` |
| ML2 設定 | `type_drivers = geneve,flat,vlan`, `tenant_network_types = geneve`, `[ml2_type_flat] flat_networks = physnet1` |
| IP | ホスト側は `br-ex` に管理 IP（構成 A）または無 IP（構成 B で管理を eth0 に分ける場合も、gateway chassis としては無 IP で可） |
| ルーティング | provider サブネットのゲートウェイが、その L2 に実在すること |
| **L2 到達性** | **同一ブロードキャストドメインで、任意の MAC / 任意の IP のフレームが素通しできること**。ここがクラウドで破綻する（§4.4） |
| DHCP | provider サブネットは `--no-dhcp` で作り、Floating IP プールとして使うのが小規模デモでは素直 |

### 4.3 実現できない組み合わせ

- **1 NIC のまま NIC を `br-ex` に入れず provider network を作る** — ブリッジに物理 NIC が入っていなければ外部に出られない。L3 だけでは成立しない。
- **NIC に IP を残したまま同じ NIC を `br-ex` にスレーブ化する** — IP は必ずブリッジ側に移す。両方に持たせると ARP が壊れる。
- **provider サブネットのゲートウェイが存在しない** — Floating IP は付くが外に出られない。
- **DHCP 有効な provider サブネットを既存 LAN に重ねる** — 既存の DHCP サーバーと競合して LAN 全体に影響する。事故になる。

### 4.4 クラウド特有の制限（重要）

**GCE / AWS の VPC は、物理 LAN と同じ L2 / provider network を提供しない。**

| 項目 | GCE | AWS |
|---|---|---|
| ブロードキャスト / マルチキャスト | *"VPC networks do not support broadcast or multicast addresses within the network."* | VPC 内で非対応（マルチキャストは Transit Gateway 経由の別機能） |
| プロミスキャスモード | 実質不可 | **ENI は非対応**。「自分宛でないフレームはハイパーバイザが配送しない」 |
| MAC 偽装 | 不可 | **Nitro が送信元/宛先 MAC を ENI 登録値と照合**。`source/dest check` の無効化は **IP のチェックしか外さず MAC は外れない** |
| 結果 | **ゲスト VM に VPC サブネットの IP を直接持たせる flat provider network は成立しない** | 同左 |

**したがってクラウド上での現実的な打ち手は 2 つ。**

1. **ホスト内部に仮想 LAN を作って閉じる（クラウドでの標準手）** — クラウド VM のホスト内部に、物理 LAN の代わりとなる L2 セグメント（uplink を持たない OVS ブリッジ）を自前で作り、そこを provider network の物理ネットワークに見立てる。この内側では任意の MAC / IP を流せるので、**Neutron の provider network のオブジェクトモデル、bridge mapping、router の external gateway、Floating IP の払い出しと DNAT/SNAT は確認できる**。外への出口はホストの NAT。
   **ただしこれは「物理 LAN で検証した」ことにはならない。** 物理セグメント上の ARP 挙動、Floating IP を実 LAN の IP として配ること、OpenStack の外のマシンからの到達、実 NIC を `br-ex` に収容したときの挙動、既存 LAN の DHCP との相互作用、VLAN は**この方法では確認できない**。これらは「物理 LAN 未確認」として明示的に残す。
2. **オーバーレイのみ** — 複数の L1 インスタンスをそのまま OpenStack ノードにする場合、ノード間の Geneve(UDP 6081) は**ユニキャスト UDP なので VPC を問題なく通る**。テナントネットワーク同士の通信は成立する。ただし provider network は成立しないため、外部接続は「コントローラ上で NAT する」形に限定され、**Floating IP を LAN の実 IP として配る検証はできない**。

### 4.5 複数テナント LAN の要否

**結論: 最小構成に追加コストを発生させないので、設定項目にはせず「作れて当たり前」として扱う。**

- OVN/Geneve のテナントネットワークは論理スイッチにすぎず、**N 個作っても追加の NIC・ブリッジ・設定ファイルは一切不要**。`type_drivers` に `geneve` が入っていれば `openstack network create` を繰り返すだけ。
- 一方、**provider 側を VLAN で複数に分けるなら**話は別で、`flat_networks` に加えて `[ml2_type_vlan] network_vlan_ranges = physnet1:100:200` と、上流スイッチの VLAN トランク設定が要る。これは小規模デモのスコープ外。
- よって Hagistack の設定項目は「provider は 1 本（flat）」に固定し、テナント LAN は利用者が後から何本でも作れる、という整理にする。

### 4.6 ゲスト VM の外部通信確認手順

```
1. provider(外部)ネットワークを作る
   openstack network create --external --provider-network-type flat \
       --provider-physical-network physnet1 public
   openstack subnet create --network public --no-dhcp \
       --subnet-range 192.168.10.0/24 --gateway 192.168.10.1 \
       --allocation-pool start=192.168.10.200,end=192.168.10.250 public-subnet

2. テナントネットワークとルーター
   openstack network create private
   openstack subnet create --network private --subnet-range 10.10.10.0/24 \
       --dns-nameserver 8.8.8.8 private-subnet
   openstack router create r1
   openstack router set r1 --external-gateway public
   openstack router add subnet r1 private-subnet

3. セキュリティグループ（ICMP と SSH）
   openstack security group rule create --proto icmp default
   openstack security group rule create --proto tcp --dst-port 22 default

4. インスタンス起動
   openstack server create --flavor m1.tiny --image cirros \
       --network private --key-name mykey demo1

5. メタデータ到達確認（ここが OVN metadata agent の検証）
   openstack console log show demo1   → cloud-init が 169.254.169.254 から取得できているか
                                        SSH 公開鍵が流し込まれているか

6. 外向き（SNAT）確認
   openstack console log show demo1 で cirros のネットワーク初期化を確認後、
   Floating IP を付けて SSH し、ゲスト内から:
       ping -c3 192.168.10.1     provider GW まで
       ping -c3 8.8.8.8          インターネットまで（L3）
       ping -c3 www.google.com   名前解決込み

7. 内向き（DNAT / Floating IP）確認
   openstack floating ip create public
   openstack server add floating ip demo1 <FIP>
   【OpenStack の外のマシンから】 ping <FIP> ; ssh -i mykey cirros@<FIP>

8. compute-add 後の追加確認
   2 台目に固定して起動し、1 台目のインスタンスとテナント内で相互 ping
   （＝ Geneve トンネルが張れていることの確認）
       openstack server create ... --availability-zone nova:<node2>
```

---

## 5. 検証環境: ローカルコンテナ / GCE / Mac / AWS

**方針**: 開発とホストを変更しない検査は**ローカルコンテナ**。実動作の必須受入は **GCE 最大 2 台**。
**Mac／UTM と物理 LAN は任意の追加検証**。**AWS は調査のみで操作しない。**

### 5.1 役割分担

| 環境 | 役割 | 必須/任意 | 費用 |
|---|---|---|---|
| **ローカルコンテナ** | シェル開発と、**ホストを変更せずに確認できる**検査（構文、ShellCheck、設定生成、入力検査、秘密情報の扱い、再実行時の安全性） | **必須** | 0 |
| **GCE node1**（`n2-standard-8` 相当・ネスト仮想化 ON） | Ubuntu 26.04 **x86_64** の all-in-one、**Nova ゲスト起動**、Horizon、**内部仮想 LAN 上の** provider network | **必須** | 従量 |
| **GCE node2**（`n2-standard-4` 相当・ネスト仮想化 ON） | compute-add、**2 台目でのゲスト起動**、**ノード間 Geneve 通信** | **必須** | 従量 |
| **Mac / UTM**（M3 24GB, arm64） | AIO 完走、arm64 対応、**物理 LAN の provider network と実 Floating IP** | **任意**（できれば追加証跡として記録。できなくても実装と GCE 検証を止めない） | 0 |
| **AWS EC2** | **調査のみ**。公式資料の確認と候補・費用条件の整理まで | **対象外**（起動・変更・動作確認をしない） | — |

### 5.2 ローカルコンテナで確認すること / しないこと

**確認すること（ホストを変更しない範囲）**

- Bash の構文（`bash -n`）
- ShellCheck が警告なしで通ること
- 設定ファイル生成の正しさ（`ini_set` の冪等性、生成結果の内容比較）
- 入力検査（未指定・不正な NIC 名・不正な CIDR・想定外 OS を**明確なエラーで拒否**するか）
- 秘密情報の扱い（固定パスワードが無いこと、生成物が 0600 で置かれること、`.gitignore` 済みであること）
- **再実行時の安全性**（2 回実行して DB 削除や設定重複が起きない。`DROP DATABASE` を書いていない）
- サブコマンド解決、`usage()`、エラー時の停止挙動（`set -euo pipefail` と `trap`）

**確認したことにしないこと（コンテナでは実証扱いにしない）**

- `nova-compute` による **KVM ゲスト VM の起動**
- カーネルモジュール・`/dev/kvm`・libvirt の実挙動
- OVS / OVN のデータプレーン動作
- **物理 LAN の疎通**、provider network、Floating IP
- systemd ユニットの実起動順序と依存解決

> コンテナはホストのカーネルを共有し、特権なしでは `/dev/kvm`・ネットワーク名前空間・カーネルモジュールを
> 本番同等に扱えない。**コンテナで通ったことをもって「OpenStack が動いた」とは書かない。**

### 5.3 Nova ゲスト起動の可否（環境別・公式資料ベース）

| 環境 | KVM（ハードウェア支援） | 備考 |
|---|---|---|
| ローカルコンテナ | **検証対象外** | 実証扱いにしない（§5.2） |
| GCE `n2-*` + `--enable-nested-virtualization` | **可**（要・実機確認） | Intel Cascade Lake。E2 / メモリ最適化 / Arm / AMD(N4D 除く) は**非対応** |
| Mac M3 + macOS 15 以降 + UTM 4.6+ | **可**（要・実機確認） | ゲストは **aarch64** になる。任意検証 |
| AWS `M7i/M8i/C7i/C8i/R7i/R8i/X8i/I7i/I7ie` | 公式に可（**今回は実施しない**） | すべて Intel 系。Graviton は対象外 |

QEMU ソフトウェアエミュレーション（`[libvirt] virt_type=qemu`）はネスト非対応環境でも動くが**極めて遅い**。
Hagistack は `/dev/kvm` の有無で自動判定し、qemu にフォールバックする場合は**明示的に警告を出す**。

### 5.4 Mac／UTM についての注意（任意検証のため、実施する場合のみ）

- ゲスト VM も **aarch64** になる。cirros / Ubuntu cloud image の arm64 を使う。
- `nova-compute-kvm` は `Architecture: all` だが、実体として **`qemu-system-arm` が要る**。
  シェル側でアーキテクチャ判定（`dpkg --print-architecture`）して切り替える。
  **ただしこの arm64 対応は初期の完了条件ではない**（§11）。x86_64 の GCE 受入が先。
- 24GB の内訳目安: macOS + UTM で 4〜6GB、AIO ノード 12GB、compute ノード 6GB。
- **物理 LAN の provider network と実 Floating IP は Mac でしか試せないが、必須ではない。**
  実施できた場合のみ追加証跡として記録し、できなければ「物理 LAN 未確認」に残す。

---

## 6. Nova のゲスト起動: KVM と QEMU の区別

| | KVM（ハードウェア支援） | QEMU（ソフトウェアエミュレーション） |
|---|---|---|
| Nova 設定 | `[libvirt] virt_type = kvm` | `[libvirt] virt_type = qemu` |
| 前提 | `/dev/kvm` が存在し、CPU の仮想化拡張がゲストに見えていること | 不要。どこでも動く |
| 確認コマンド | `ls -l /dev/kvm`, `egrep -c '(vmx\|svm)' /proc/cpuinfo`（x86）, `kvm-ok` | — |
| 速度 | 実用的 | 10〜50 倍遅い。cirros の起動確認が精一杯 |
| Hagistack での扱い | **自動判定**。`/dev/kvm` があれば kvm を使う | 無ければ qemu にフォールバックし、**その旨を明示的にログに出す**（黙って遅い構成にしない） |

### 6.1 GCE のネスト仮想化条件（公式）

- L1 の**非対応**: E2 VM / メモリ最適化 VM / **Arm プロセッサ搭載 VM** / **AMD 搭載 VM（ただし N4D は対応）** / H4D。
- CPU プラットフォームは **Intel Haswell 以降**が必要。
- L1 内で使えるハイパーバイザは **Linux KVM のみ**（Hyper-V 不可）。
- 有効化は `enableNestedVirtualization` フラグ（旧来のライセンスキー方式より推奨）。
- 性能: CPU バウンドで **10% 以上**、I/O バウンドで**それ以上**の低下。

### 6.2 AWS のネスト仮想化条件（公式・2026-02-16 以降）

「EC2 全般で可能／不可能」では括れない。**インスタンスタイプで決まる。**

- **対応タイプ**
  - 汎用: `M7i`, `M7i-flex`, `M8i`, `M8id`, `M8i-flex`
  - コンピュート最適化: `C7i`, `C7i-flex`, `C8i`, `C8id`, `C8i-flex`
  - メモリ最適化: `R7i`, `R7iz`, `R8i`, `R8id`, `R8i-flex`, `X8i`
  - ストレージ最適化: `I7i`, `I7ie`
- **アーキテクチャ**: 上記はすべて Intel 系。**Graviton(Arm) 系（`*g`）は対象外**。
- **ハイパーバイザ**: L1 では **KVM と Hyper-V** が対応。
- **有効化**: 起動時 `--cpu-options "NestedVirtualization=enabled"` / 既存は停止後 `modify-instance-cpu-options --nested-virtualization enabled`。
- **料金**: **追加料金なし**。
- **リージョン**: 全商用リージョン。
- **仕組み**: Nitro が Intel VT-x をインスタンスへ引き渡す（L0=Nitro, L1=EC2, L2=ゲスト）。
- **注意**: 性能要件が厳しい場合は AWS 自身がベアメタルを推奨している。
- **確認方法（公式）**:
  ```
  aws ec2 describe-instance-types --region ap-northeast-1 \
    --filters "Name=processor-info.supported-features,Values=nested-virtualization" \
    --query "InstanceTypes[].InstanceType" --output text
  ```
  → **受入前にこのコマンドで当日の対応状況を実確認すること**（一覧は変わりうる）。

### 6.3 ネットワークについて仮定しないこと

§4.4 のとおり、**GCE の VPC も AWS の VPC も、通常の物理 LAN と同じ L2 / provider network は提供しない**。
「ネスト仮想化が使える ＝ OpenStack のネットワーク検証がそのままできる」ではない。
クラウドで L2 を扱うなら **ホスト内部に仮想 LAN を作って閉じる**（§4.4 の打ち手 1）。
**そこで通ったことを「物理 LAN で検証済み」と書かない。** 区分けは `HAGISTACK_VERIFICATION_SCOPE_2026-09-26.md` §5 に従う。

---

## 7. 費用と実機受入

### 7.1 料金情報の取得条件（明記）

| 項目 | 内容 |
|---|---|
| 取得日時 | **2026-09-26**（本調査時点） |
| AWS EC2 料金の出典 | AWS Price List Bulk API `AmazonEC2` / `ap-northeast-1`。**publicationDate 2026-09-25T17:45:21Z** |
| AWS データ転送料金の出典 | AWS Price List Bulk API `AWSDataTransfer` / `ap-northeast-1`。**publicationDate 2026-09-16T13:22:08Z** |
| リージョン | **ap-northeast-1（東京）** |
| 課金条件 | **オンデマンド / Shared テナンシー / Linux / 事前導入ソフトなし / CapacityStatus=Used** |
| 通貨 | **USD**（為替換算はしていない） |
| 含まないもの | 消費税、Savings Plans / RI 割引、Elastic IP 料金、スナップショット、NAT Gateway、その他付帯サービス |
| **GCE 料金** | **記載しない**。Cloud Billing Catalog API は API キー必須で 403、公式価格ページは JS レンダリングで HTML に価格が含まれず、**一次情報として取得できなかったため**。推測値は書かない |

### 7.2 AWS: 確認済み単価（東京・オンデマンド・Linux・Shared）

| インスタンスタイプ | vCPU | メモリ | USD / 時 | ネスト仮想化 |
|---|---|---|---|---|
| `m8i.xlarge`  | 4  | 16 GiB | **0.27342** | 対応 |
| `m8i.2xlarge` | 8  | 32 GiB | **0.54684** | 対応 |
| `m8i.4xlarge` | 16 | 64 GiB | **1.09368** | 対応 |
| `m7i.xlarge`  | 4  | 16 GiB | **0.26040** | 対応 |
| `m7i.2xlarge` | 8  | 32 GiB | **0.52080** | 対応 |
| `m7i.4xlarge` | 16 | 64 GiB | **1.04160** | 対応 |
| `c8i.2xlarge` | 8  | 16 GiB | **0.47188** | 対応 |
| `c8i.4xlarge` | 16 | 32 GiB | **0.94376** | 対応 |
| `r8i.2xlarge` | 8  | 64 GiB | **0.67032** | 対応 |

**ストレージ / 通信（東京）**

| 項目 | 単価 |
|---|---|
| EBS gp3 ボリューム | **0.096 USD / GB-月** |
| EBS gp3 追加 IOPS（3,000 のベースライン超過分） | **0.006 USD / IOPS-月** |
| インターネット向け送信（0〜10 TB/月） | **0.114 USD / GB** |
| 同（10〜50 TB/月） | 0.089 USD / GB |
| 同（無料枠） | **月 100 GB まで 0 USD（全リージョン合算）** |
| 受信（インターネットから） | 0 USD |

### 7.3 AWS 実機受入候補

前提: **L1 インスタンス 1 台の内側に、ネストで OpenStack ノードを作る**（§4.4 打ち手 1）。
これなら all-in-one と compute-add、および管理 LAN / 外部 LAN 分離を、1 台の課金で全部検証できる。

| 候補 | インスタンス | 台数 | 用途 | ディスク | 稼働時間の想定 |
|---|---|---|---|---|---|
| **A: 最小（AIO のみ）** | `m8i.2xlarge`（8vCPU / 32GiB） | 1 | 内側に AIO 1 ノード（12GiB）+ ゲスト VM | gp3 100 GB | 1 日 8 時間 × 5 日 = 40 時間 |
| **B: 標準（AIO + compute-add）推奨** | `m8i.4xlarge`（16vCPU / 64GiB） | 1 | 内側に AIO(16GiB) + compute(12GiB) + 仮想 provider LAN | gp3 200 GB | 1 日 8 時間 × 5 日 = 40 時間 |
| **C: 分散（VPC 越しの複数ノード）** | `m8i.2xlarge` | 2 | ノードを別 EC2 に分ける。Geneve は通るが **provider network は作れない**（§4.4） | gp3 100 GB × 2 | 40 時間 |

**見積もりの組み立て方（条件を明示した形）**

```
EC2 費用   = 単価(USD/時) × 台数 × 稼働時間
   例 候補B: 1.09368 × 1 × 40 = 43.75 USD
   例 候補A: 0.54684 × 1 × 40 = 21.87 USD
   例 候補C: 0.54684 × 2 × 40 = 43.75 USD

EBS 費用   = 0.096 USD/GB-月 × GB × (保持日数 / 30)
   ※ インスタンス停止中も EBS は課金される。検証後に削除しないと課金が続く
   例 候補B: 0.096 × 200 × (7/30) = 4.48 USD

通信費用   = インターネット向け送信量に依存。月 100 GB まで無料。
   本用途（パッケージ取得は「受信」なので無料、外向きは SSH/画面操作程度）では
   100 GB の無料枠に収まる想定。ただし実測して確認すること。

合計(候補B, 7日保持・40時間稼働) ≈ 43.75 + 4.48 ≈ 48.2 USD（税別・割引なし・東京・2026-09-25 時点単価）
```

**注意: 上記は上の単価と条件から算出した金額であり、実際の請求は稼働時間・保持日数・通信量の実績で変わる。**

### 7.4 GCE 実機受入候補と費用

**GCE の料金は、その後 Google Cloud Billing Catalog API（利用者の gcloud 認証・読み取り専用）から取得できた。**
確定した単価・算出内訳・前提条件は **`HAGISTACK_VERIFICATION_SCOPE_2026-09-26.md` §7** に記載する（本書では重複させない）。

概要のみ:

| 項目 | 内容 |
|---|---|
| リージョン | `asia-northeast1`（東京） |
| SKU の effectiveTime | 2026-09-26T07:00:00Z |
| マシンタイプ | **ネスト仮想化対応が必須**。E2 / メモリ最適化 / Arm / AMD(N4D 除く) は不可。`n2-standard-4 / 8 / 16` が `asia-northeast1-a` で利用可能 |
| 想定構成 | node1 = `n2-standard-8`、node2 = `n2-standard-4`、各 `pd-balanced` 100GB |
| **概算** | **前提付きで約 37.2 USD**（各 40 時間稼働・ディスク 7 日保持・外部 IPv4 2 個）。**確定請求額ではない。** 未算入・未確定の項目は同書 §7.5 を参照 |

### 7.5 受入環境の推奨（改訂後）

1. **ローカルコンテナ** — 費用ゼロ。シェル開発と、ホストを変更しない検査（§5.2）。**必須**
2. **GCE node1 / node2（最大 2 台）** — x86_64 での実動作受入。**必須**
3. **Mac（M3 / UTM）** — arm64 と物理 LAN の追加証跡。**任意**
4. **AWS** — **調査のみ**。今回は起動・変更・動作確認を行わない

---

## 8. 旧コードの整理（今回は削除しない）

**確認結果: 古いディレクトリを削除しても Git 履歴から完全に復元できる。**

| 確認 | 結果 |
|---|---|
| 履歴の存在 | `git log --all -- centos6.2` で `387ef96` `de1e6f1` `26d9303` `0c54b7e` `cb9797d` 等の履歴あり |
| 内容取得 | `git show HEAD:centos6.2/hagistack_controller.sh` で中身を取得できる |
| リポジトリ規模 | `in-pack: 691` オブジェクト、`size-pack: 198.97 KiB`。**全履歴で 200KB 弱**。容量的に残しても一切困らない |
| リモート | `origin https://github.com/hagix9/hagistack.git`（push 済み。`master` は up to date） |

**復元方法（将来必要になったとき）**

```
git log --all --oneline -- ubuntu13.10          # 削除前の最終コミットを探す
git show <commit>:ubuntu13.10/hagistack_controller_neutron.sh   # 内容を見る
git checkout <commit> -- ubuntu13.10/           # 作業ツリーに復元
git log --diff-filter=D --name-only --oneline   # 削除されたファイルを一覧
```

**留意点**

- 復元できるのは **コミット済みの内容だけ**。`rocky10.2/` と `ubuntu26.04/` は空ディレクトリで Git 未追跡（Git は空ディレクトリを追跡しない）ため、そもそも履歴が無い。
- 履歴からの復元は `origin` にも push 済みであることが前提。**削除コミットを push する前に、origin が最新であることを確認する**（現在は clean / up to date なので問題なし）。
- 容量が 200KB 程度である以上、削除する積極的な理由は薄い。**`legacy/` へ移動して残す**のが最も安全で、履歴も途切れない（`git mv` なら追跡も維持される）。

---

## 9. 利用者に指定してもらう最小設定項目案

**原則: 項目を極限まで減らす。パスワードは Git に置かず、自動生成して `/etc/hagistack/secrets.env`(0600) に保存する。**

### 9.1 all-in-one で指定する項目

| 変数 | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `MGMT_IP` | 任意 | 既定 NIC の IP を自動検出 | 管理 LAN の IP。API エンドポイントの bind と Geneve の終端 |
| `EXT_NIC` | **必須** | なし | 外部/プロバイダー LAN 側の NIC 名。1 NIC 構成なら管理と同じ名前を指定（その場合はシェルが IP を `br-ex` へ移す） |
| `PROVIDER_CIDR` | **必須** | なし | 外部 LAN のネットワーク。例 `192.168.10.0/24` |
| `PROVIDER_GATEWAY` | **必須** | なし | 外部 LAN のゲートウェイ。例 `192.168.10.1` |
| `FLOATING_START` | **必須** | なし | Floating IP プール開始。例 `192.168.10.200` |
| `FLOATING_END` | **必須** | なし | Floating IP プール終了。例 `192.168.10.250` |
| `ADMIN_PASSWORD` | 任意 | **自動生成** | admin のパスワード。指定しなければランダム生成して secrets に保存 |
| `DNS_SERVER` | 任意 | `PROVIDER_GATEWAY` | テナントサブネットの DNS |
| `TENANT_CIDR` | 任意 | `10.10.10.0/24` | デモ用テナントサブネット |
| `VIRT_TYPE` | 任意 | **自動判定**（`/dev/kvm` の有無） | `kvm` / `qemu` |

**実質的に利用者が必ず書くのは 5 項目**（`EXT_NIC`, `PROVIDER_CIDR`, `PROVIDER_GATEWAY`, `FLOATING_START`, `FLOATING_END`）。

### 9.2 compute-add で指定する項目

| 変数 | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `CONTROLLER_IP` | **必須** | なし | コントローラの管理 IP |
| `MGMT_IP` | 任意 | 自動検出 | このノードの管理 IP（Geneve 終端） |
| `JOIN_SECRET` | **必須** | なし | コントローラの `/etc/hagistack/secrets.env` から持ってくる。RabbitMQ / Keystone / OVN SB の接続情報一式 |
| `VIRT_TYPE` | 任意 | 自動判定 | `kvm` / `qemu` |

**実質 2 項目**（`CONTROLLER_IP` と `JOIN_SECRET`）。
`JOIN_SECRET` は、コントローラ側で `hagistack join-token` のようなサブコマンド／関数を用意して 1 行で出力させ、
それをコンピュート側に貼る運用にすると、利用者の手数が最小になる。**この値は絶対に Git に入れない。**

### 9.3 設定の渡し方

旧シェルの `stack.env` は良い設計なので継承する。優先順位:

```
1. コマンドライン引数（--ext-nic eth1 等）
2. 環境変数
3. ./hagistack.env         （利用者が書くファイル。.gitignore に入れる）
4. シェル内の既定値／自動検出
```

`hagistack.env.example` をコミットし、**実体の `hagistack.env` と `/etc/hagistack/secrets.env` は `.gitignore`** に入れる。

---

## 10. 2 シェル案 / 1 シェル案の比較と推奨

### 10.1 比較

| 観点 | 案A: シェル 2 本<br>`hagistack-allinone.sh` / `hagistack-compute-add.sh` | 案B: サブコマンド 1 本<br>`hagistack all-in-one` / `hagistack compute-add` |
|---|---|---|
| 利用者から見た分かりやすさ | ファイル名がそのまま操作名。**説明不要** | `--help` を読む必要が 1 段ある |
| 共通処理の扱い | 共通部分（ログ、ini 編集、冪等ヘルパー、KVM 判定、パッケージ導入）を**両方に書くか、`lib.sh` を別途置くことになる** | **自然に 1 ファイル内で共有できる** |
| コード重複 | 放置すると必ず重複し、**旧 Hagistack で実際に起きた「片方だけ直る」問題を再発させる**（`ubuntu13.10` の controller と compute で nova.conf 生成がほぼ丸ごと重複していた） | 重複しない |
| ファイル数 | 2、ただし共通化すると 3（+`lib.sh`）で、**`lib.sh` の置き場所と読み込みパス解決という新たな複雑さが生まれる** | **1** |
| 配布 | 2〜3 ファイルを揃えて置く必要がある | **1 ファイルを `curl` で落として実行できる** |
| 行数の見込み | 各 700〜900 行 + lib 200 行 | 1,200〜1,500 行 |
| 1 ファイルの可読性 | 1 本あたりは短い | 長い。ただし関数分割と明確なセクション区切りで対処可能 |
| 拡張（将来 `status` / `destroy` / `join-token` を足す） | シェルが増え続ける | **サブコマンドを 1 個足すだけ** |
| テスト | 2 つのエントリポイント | 1 つ。`shellcheck` も 1 ファイル |

### 10.2 推奨: **案B（サブコマンドを持つ 1 本）**

理由は 3 つ。

1. **旧 Hagistack が壊れた主因が重複だった。** `hagistack_controller_neutron.sh` と `hagistack_compute_neutron.sh` は
   nova.conf の生成ブロックがほぼ同一なのに、compute 側にだけ `for proc in proc in compute` というタイプミスが残っていた。
   2 本に分けると、この構造的な欠陥を再生産する。
2. **all-in-one と compute-add は処理の 6 割以上が共通。** OS 準備、冪等ヘルパー、ini 編集、KVM 判定、OVS/OVN セットアップ、
   libvirt、検証コマンド群。共有しないという選択肢が現実的にない。
3. **「単純」の意味は「ファイルが少ない」ではなく「読む場所が 1 か所」。** 1 ファイルなら、
   利用者も保守者も「これを読めば全部書いてある」と言える。`lib.sh` の読み込みパス解決（`$(dirname "$0")` の罠）も要らない。

**ただし案B を採るなら守ること**

- `usage()` を最初に置き、`hagistack all-in-one` / `hagistack compute-add` / `hagistack status` / `hagistack join-token` を明記する。
- サブコマンド解決は `case "$1" in` の 1 か所だけ。分散させない。
- 関数を `phase_` 接頭辞で揃え、all-in-one と compute-add の本体を**「呼ぶ関数を並べただけ」に保つ**。ここを読めば流れが分かる状態にする。
  ```
  cmd_all_in_one() {
      phase_preflight; phase_base_packages; phase_database; phase_rabbitmq;
      phase_keystone; phase_glance; phase_placement;
      phase_ovs_ovn; phase_neutron; phase_nova_control; phase_nova_compute;
      phase_horizon; phase_bootstrap_resources; phase_verify
  }
  cmd_compute_add() {
      phase_preflight; phase_base_packages_compute; phase_ovs_ovn_compute;
      phase_neutron_metadata; phase_nova_compute; phase_verify_compute
  }
  ```
- 案B でどうしても長すぎると判断したら、そのときに初めて分割する。**最初から分けない。**

---

## 11. 実装に進むための受入条件

**必須（これを満たさなければ実装完了としない）と、任意（満たせなくても止めない）を分ける。**
受入結果の記録様式（区分 A / B / C）は `HAGISTACK_VERIFICATION_SCOPE_2026-09-26.md` §5 に従う。

### 11.1 必須 — ローカルコンテナ（ホストを変更しない検査）

- [ ] `bash -n` が通る
- [ ] `shellcheck` が警告なしで通る
- [ ] サブコマンド解決と `usage()` が期待どおり
- [ ] `set -euo pipefail` + `trap` により、途中失敗時は**明確なエラーメッセージを出して停止**する（半端に完了しない）
- [ ] 設定生成が冪等（`ini_set` を 2 回適用しても結果が同じ。`tee -a` による重複追記が無い）
- [ ] 入力検査: 想定外 OS / 未指定の必須項目 / 不正な NIC 名 / 不正な CIDR を**分かりやすいエラーで拒否**する
- [ ] **固定パスワードがソースに 1 つも無い**（`git grep -iE 'pass(word)?\s*=\s*[a-z0-9]'` で該当なし）
- [ ] 生成した秘密情報が 0600 で置かれ、`hagistack.env` / `secrets.env` が `.gitignore` 済み
- [ ] **再実行時の安全性**: 2 回実行しても破壊しない。ソースに `DROP DATABASE` が無い
- [ ] AppArmor 無効化・libvirt の無認証 TCP 公開・MariaDB の 0.0.0.0 公開を**行うコードが無い**

> **コンテナでの合格は「ホストを変更せず確認できる範囲」に限る。**
> `nova-compute` の KVM ゲスト起動・OVS/OVN のデータプレーン・物理 LAN 疎通は、
> ここで通ってもコンテナでは実証扱いにしない（§5.2）。

### 11.2 必須 — GCE node1（all-in-one / Ubuntu 26.04 x86_64）

- [ ] クリーンな Ubuntu 26.04 に対し **1 コマンド**で完走する
- [ ] `openstack endpoint list` に keystone / glance / placement / nova / neutron が並ぶ
- [ ] `openstack compute service list` が全て `up`
- [ ] `openstack network agent list` の OVN Controller / Metadata Agent が `Alive`
- [ ] `openstack resource provider list` に compute ノードが出る
- [ ] **Nova でゲスト VM（cirros）が `ACTIVE` になる**
- [ ] `openstack console log show` で **cloud-init がメタデータを取得できている**（SSH 鍵が入っている）
- [ ] **Horizon** にログインでき、インスタンス一覧が見える
- [ ] **内部仮想 LAN 上の** provider network が作成でき、Floating IP を払い出して付与できる
- [ ] **node1 ホストから** その Floating IP へ ping / SSH できる
- [ ] ゲスト VM からインターネットへ ping が通る（ホスト NAT を挟む）
- [ ] **2 回目の実行が破壊せずに完走する**

### 11.3 必須 — GCE node2（compute-add）

- [ ] `CONTROLLER_IP` + `JOIN_SECRET` の 2 項目だけで完走する
- [ ] コントローラ側で `openstack compute service list` に 2 台目が `up` で出る
- [ ] `nova-manage cell_v2 discover_hosts` が**シェル内で自動実行される**（利用者に手動実行させない）
- [ ] **2 台目を指定してゲスト VM を起動できる**
- [ ] **1 台目のゲストと 2 台目のゲストがテナント内で相互 ping できる**（= ノード間 Geneve 通信の確認）
- [ ] ノード間に必要な通信（Geneve / OVN SB / RabbitMQ / Keystone / Glance / Placement）が**実際に通ることを受入時に確認する**
- [ ] 再実行が安全

### 11.4 任意 — 追加証跡（満たせなくても実装と GCE 検証を止めない）

- [ ] Mac／UTM 上の Ubuntu 26.04 **arm64** で AIO が完走する
- [ ] arm64 向けパッケージ切り替え（`qemu-system-arm`）が機能する
- [ ] Mac の bridged NIC による**物理 LAN 上の provider network**
- [ ] **物理 LAN 上の実 Floating IP**（OpenStack の外のマシンから到達）
- [ ] 2 NIC 構成（管理 / 外部を別 NIC に分ける）
- [ ] 1 NIC 構成での管理 IP の `br-ex` 移設（Netplan による再起動耐性、SSH 切断時の警告）

> **GCE の内部仮想 LAN 上で Floating IP が通っても、物理 LAN 上の Floating IP を検証済みとは書かない。**
> 物理 NIC の `br-ex` 収容、1 NIC での管理 IP 移設、物理 VLAN は**今回は未確認として残してよい**。

### 11.5 対象外 — AWS

- [ ] **今回は調査のみ。** EC2 の起動・変更・動作確認は受入条件に含めない

### 11.6 Rocky Linux について

- [ ] **今回は実装しない。** `rocky10.2/` は空のまま残すか、`README` に
      「配布 RPM による OpenStack 2026.1 の直接構築は §0 の理由により未対応。他の手段は未調査」と明記する
- [ ] 再評価のトリガ（§0 の 3 条件）を README に書いておき、定期的に確認する

---

## 12. 最初の小さな実装単位

いきなり全部書かない。**動くものを最短で 1 つ作り、そこに足していく。**

### Step 1（最初の 1 単位）: `hagistack` の骨格 + preflight + 基盤 3 点

**成果物**: `ubuntu26.04/hagistack`（実行可能な 1 ファイル）
**検証場所**: **ローカルコンテナ**（ホストを変更しない範囲。§5.2）

**含めるもの**

1. `usage()` とサブコマンド解決（`all-in-one` / `compute-add` / `status` は枠だけ）
2. `set -euo pipefail` と `trap` によるエラー行の表示
3. ログ関数（`log_info` / `log_warn` / `log_error` / `log_step`）
4. 設定の読み込み優先順位（引数 → 環境変数 → `hagistack.env` → 既定値／自動検出）
5. シークレット生成と `/etc/hagistack/secrets.env`(0600) への保存・再読込
6. 冪等ヘルパー `ini_set <file> <section> <key> <value>`（`crudini` を使うか自前実装）
7. `phase_preflight`:
   - OS が Ubuntu 26.04 か（違えば**明確に拒否**）
   - アーキテクチャ判定（amd64 / arm64）→ 導入する qemu パッケージを決定
   - `/dev/kvm` の有無 → `VIRT_TYPE` 決定、**qemu になる場合は警告を出す**
   - メモリ / ディスク空き容量の下限チェック
   - `EXT_NIC` の存在確認、1 NIC 構成かどうかの判定と警告
8. `phase_base_packages`（`apt-get update` + 共通パッケージ）
9. `phase_database`（MariaDB。**`CREATE DATABASE IF NOT EXISTS` のみ。DROP は書かない**）
10. `phase_rabbitmq`
11. `hagistack status`（この時点では MariaDB / RabbitMQ の稼働確認だけ）

**Step 1 の完了条件（すべてローカルコンテナで確認する）**

- Ubuntu 26.04 のコンテナ内で `./hagistack all-in-one` を実行すると、preflight → 基盤 3 点まで通って正常終了する
- **2 回連続で実行しても壊れない**（DB 削除も設定重複も起きない）
- `bash -n` と `shellcheck` が通る
- ソースに固定パスワードが 1 つも無い
- 想定外の OS / NIC 指定ミスで、**分かりやすいエラーを出して止まる**

**この時点で確認しないこと**: KVM ゲスト起動、OVS/OVN のデータプレーン、物理 LAN 疎通。
コンテナでは実証扱いにしない（§5.2）。アーキテクチャ判定のコードは書くが、
**arm64 での実動作は初期の完了条件ではない**（§11.4 の任意項目）。

**なぜここを最初にするか**

旧 Hagistack の失敗（非冪等、固定パスワード、`set -e` 無し、エラーを無視して走り切る）は、
すべて**この骨格部分の欠落**が原因だった。OpenStack のサービスを 1 つも入れる前に、
**壊れない土台と、2 回実行しても安全な仕組みを先に確立する。**

### 以降の単位（参考）

| Step | 場所 | 内容 | 完了条件 |
|---|---|---|---|
| 2 | コンテナ | Keystone | 設定生成と冪等性。`token issue` は GCE で確認 |
| 3 | コンテナ | Glance + Placement | 同上 |
| 4 | コンテナ | OVS + OVN + Neutron server の**設定生成** | 生成内容の検査（データプレーンは GCE で確認） |
| 5 | コンテナ | Nova（control + compute）+ cells v2 の**設定生成と手順** | 同上 |
| 6 | コンテナ | 初期リソース投入ロジック（flavor / image / network / router / secgroup / keypair） | `show \|\| create` の冪等性 |
| 7 | コンテナ | Horizon 設定 | 生成内容の検査 |
| 8 | コンテナ | `compute-add` サブコマンド + `join-token` | 生成内容と入力検査 |
| 9 | **GCE node1** | **all-in-one の実受入** | **§11.2 を全て満たす** |
| 10 | **GCE node2** | **compute-add の実受入** | **§11.3 を全て満たす** |
| 11 | GCE | 検証後に VM とディスクの状態を確認し、費用が残らないようにする | `destroy` 後にインスタンスとディスクが消えていること |
| 12 | Mac（任意） | arm64 / 物理 LAN の追加証跡 | 取れれば記録。取れなければ「未確認」に残す |

**コンテナで通せるところは全部コンテナで通してから GCE に上がる。** GCE の稼働時間を最小にするため。

---

## 付録: 本調査で実行した確認コマンド（再現用・すべて読み取り専用）

```bash
# リポジトリ
git status ; git log --oneline -20 ; git ls-files ; git count-objects -vH
git log --all --oneline -- centos6.2
git show HEAD:centos6.2/hagistack_controller.sh

# Ubuntu 26.04 パッケージ存在確認
for p in keystone glance-api placement-api nova-api nova-compute neutron-server \
         neutron-ovn-metadata-agent openstack-dashboard ovn-central ovn-host \
         openvswitch-switch rabbitmq-server mariadb-server memcached ; do
  curl -sS -o /dev/null -w "$p %{http_code}\n" "https://packages.ubuntu.com/resolute/$p"
done

# Ubuntu リリース状態
curl -sSL https://api.launchpad.net/1.0/ubuntu/series

# CentOS Stream Cloud SIG（10 に OpenStack が無いことの確認）
curl -sS https://mirror.stream.centos.org/SIGs/10-stream/cloud/x86_64/
curl -sS https://mirror.stream.centos.org/SIGs/9-stream/cloud/x86_64/

# RDO の EL10 ビルド状況
curl -sS https://trunk.rdoproject.org/
curl -sS https://trunk.rdoproject.org/centos10/status_report.csv -o rdo10.csv
tail -n +2 rdo10.csv | awk -F, '{print $6}' | sort | uniq -c
tail -n +2 rdo10.csv | awk -F, '$6=="FAILED"{print $1}' | sort

# Rocky 10 に OVS/OVN が無いことの確認
curl -sS https://dl.rockylinux.org/pub/rocky/10/
curl -sS https://dl.rockylinux.org/pub/rocky/10/AppStream/x86_64/os/Packages/o/
curl -sS https://dl.rockylinux.org/pub/rocky/10/NFV/x86_64/os/Packages/
curl -sS https://dl.rockylinux.org/pub/sig/10/cloud/x86_64/

# AWS 料金（一次情報）
curl -sS https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/region_index.json
curl -sS https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSDataTransfer/current/region_index.json
# → 各 region の index.csv をストリーム処理して
#    TermType=OnDemand / Tenancy=Shared / OS=Linux / PreInstalledSW=NA / CapacityStatus=Used で抽出

# AWS ネスト仮想化対応タイプ（受入前に当日実行すること）
aws ec2 describe-instance-types --region ap-northeast-1 \
  --filters "Name=processor-info.supported-features,Values=nested-virtualization" \
  --query "InstanceTypes[].InstanceType" --output text
```

---

## 付録: 本調査で行っていないこと（正直な限界）

- **OpenStack を一度も実際に構築していない。** 本レポートは公開リポジトリの内容とパッケージの存在確認、
  および公式ドキュメントの記述に基づく。Ubuntu 26.04 の**条件付き GO** は「部材が揃っていることの確認」であって、
  **「組み上げて動いた」ことの確認ではない**。だから「GO」ではなく「条件付き GO」としている。
- **Nova によるゲスト VM の起動を一度も確認していない。**
- **Ubuntu 26.04 の各パッケージの中身（ユニット名、既定の bind アドレス、postinst の自動化範囲）を検証していない。**
- **Rocky 10.2 について調べたのは「配布 RPM の入手性」だけ。** ソースビルド・自前パッケージング・コンテナ利用などは
  調べていないので、可否を判断していない。「いかなる方法でも不可能」とは書いていない。
- **GCE / AWS / Mac のいずれでも、実際にインスタンスを起動していない。**
  GCE については読み取り専用の `describe` / `list` と料金 API の参照のみ。
- **AWS は API を一度も呼んでいない**（認証不要の公開料金エンドポイントを除く）。
- **GCE の `default-allow-internal` は「既存のファイアウォール規則としてそう設定されている」ことを確認しただけ。**
  Geneve / OVN / RabbitMQ 等が実際に疎通するかは、GCE 受入時に確認する。


- **OpenStack を一度も実際に構築していない。** 本レポートは公開リポジトリの内容とパッケージの存在確認、
  および公式ドキュメントの記述に基づく。Ubuntu 26.04 の GO 判定は「パッケージが揃っている」ことの確認であって、
  「組み上げて動いた」ことの確認ではない。
- **Ubuntu 26.04 の各パッケージの中身（ユニット名、既定の bind アドレス、postinst の自動化範囲）を検証していない。**
  §0 の未確認事項に挙げたとおり、実装の最初の段階で確認が要る。
- **GCE の料金を取得できていない。** 推測値は書いていない。
- **AWS / GCE / Mac のいずれでも、実際にインスタンスを起動していない。**
