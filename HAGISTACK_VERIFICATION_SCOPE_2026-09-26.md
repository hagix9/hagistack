# Hagistack 検証範囲

- 作成日: 2026-09-26（検証方針の改訂を反映）
- 位置づけ: `HAGISTACK_RENEWAL_RESEARCH_2026-09-26.md` の **検証環境・費用・受入条件を詳述する**。両書は整合している。
- 本書での実行: **読み取り専用のみ**。GCE VM の作成・起動・変更・削除、AWS の操作、OpenStack の導入、Sinter リポジトリへの書き込みは**一切行っていない**。

## 方針（一行で）

> **開発とホストを変更しない検査は「ローカルコンテナ」。実動作の必須受入は「GCE 最大 2 台」。
> Mac／UTM と物理 LAN は「任意の追加検証」。AWS は「調査のみ」。**

| 環境 | 役割 | 必須/任意 |
|---|---|---|
| **ローカルコンテナ** | シェル開発、構文、ShellCheck、設定生成、入力検査、秘密情報の扱い、再実行時の安全性 | **必須** |
| **GCE node1** | Ubuntu 26.04 x86_64 の all-in-one、Nova ゲスト起動、Horizon、**内部仮想 LAN 上の** provider network | **必須** |
| **GCE node2** | compute-add、2 台目でのゲスト起動、ノード間 Geneve 通信 | **必須** |
| **Mac / UTM** | AIO 完走、arm64 対応、**物理 LAN の** provider network と実 Floating IP | **任意**（できれば追加証跡。できなくても止めない） |
| **AWS EC2** | 公式資料の調査と候補・費用条件の整理 | **対象外**（起動・変更・動作確認をしない） |

---

## 1. 判定

| 対象 | 判定 |
|---|---|
| Ubuntu Server 26.04 LTS + OpenStack 2026.1 | **条件付き GO** |
| Rocky Linux 10.2 + OpenStack 2026.1（**配布 RPM による直接構築**） | **NO-GO** |
| Rocky Linux 10.2（ソースビルド等、調査していない手段） | **未調査（判定しない）** |

**Ubuntu 26.04 が「条件付き GO」である理由**
必要パッケージがディストリ標準リポジトリだけで入手できることは実地確認済み。
**一方で、OpenStack の構築もゲスト VM の起動も未検証。**
**§5 の区分 A・B に合格して初めて「動作確認済み」と書く。**

**Rocky 10.2 の NO-GO の適用範囲**
NO-GO と言えるのは「配布されている RPM を `dnf` で導入して OpenStack 2026.1 を直接構築する」手段のみ。
OpenStack 本体も OVS/OVN も EL10 向け RPM が存在しないため、この手段では部材が揃わない。
**ソースビルド・自前パッケージング・コンテナ利用などは調べていないので可否を判断しない。**
いずれにせよ**今回の実装対象からは外す**。

---

## 2. 既存 GCE 環境の実確認（読み取り専用）

`sinter-acceptance/gce.sh status` を実行（README に *"`status` is strictly read-only."* と明記されており、
`gcloud compute instances describe` / `disks describe` しか呼ばない）。

```
project: sinter-508914   account: hagix9@gmail.com

TARGET    STATE       ZONE               MACHINE   IMAGE             DISK_GB EXT_IP
ubuntu24  TERMINATED  asia-northeast1-a  e2-micro  ubuntu-2404-lts   10      ONE_TO_ONE_NAT
ubuntu26  TERMINATED  asia-northeast1-a  e2-micro  ubuntu-2604-lts   10      ONE_TO_ONE_NAT
rocky9    TERMINATED  asia-northeast1-a  e2-micro  rocky-linux-9     20      ONE_TO_ONE_NAT
rocky10   TERMINATED  asia-northeast1-a  e2-micro  rocky-linux-10    20      ONE_TO_ONE_NAT
rhel9     TERMINATED  asia-northeast1-a  e2-small  rhel-9-server     20      ONE_TO_ONE_NAT
rhel10    TERMINATED  asia-northeast1-a  e2-small  rhel-10-server    20      ONE_TO_ONE_NAT
alma9     TERMINATED  asia-northeast1-a  e2-small  almalinux-9       10      ONE_TO_ONE_NAT
alma10    TERMINATED  asia-northeast1-a  e2-small  almalinux-10      10      ONE_TO_ONE_NAT

targets: 10   RUNNING: 0   MISSING: 2
```

### 2.1 わかったこと

| 事実 | Hagistack への影響 |
|---|---|
| **全 8 台が `e2-micro` / `e2-small`** | **E2 は GCE 公式でネスト仮想化 非対応**（除外リスト先頭）。→ **既存フリートでは Nova の KVM ゲスト起動を検証できない** |
| `ubuntu26` が既に存在（e2-micro / 10GB） | OS の素性確認には使えるが、**メモリ 1GB / ディスク 10GB では OpenStack AIO は載らない** |
| `rocky102` が既に存在 | Rocky は今回の実装対象外のため使わない |
| **全台 TERMINATED** | 現在コンピュート課金は発生していない（ディスクは残るので容量課金は別途） |
| ディスク 10〜20GB | OpenStack + Glance イメージ + Nova インスタンスには足りない（100GB 程度必要） |
| 全台に `default-schedule-1` スナップショットポリシー | Hagistack 用 VM にも付くかは create 時のオプション次第。**課金要素として認識しておく** |

**結論: 既存フリートは Hagistack の検証に流用できない。Hagistack 用に別の VM が要る（今回は作らない）。**

### 2.2 ネットワーク環境の実確認（読み取り専用）

```
$ gcloud compute networks list --project=sinter-508914
NAME     SUBNET_MODE  BGP_ROUTING_MODE
default

$ gcloud compute networks subnets list --filter="region:asia-northeast1"
NAME     NETWORK  REGION           RANGE
default  default  asia-northeast1  10.146.0.0/20

$ gcloud compute firewall-rules list
NAME                     NETWORK  DIRECTION  ALLOW
default-allow-icmp       default  INGRESS    icmp
default-allow-internal   default  INGRESS    tcp:0-65535,udp:0-65535,icmp
default-allow-ssh        default  INGRESS    tcp:22
default-allow-rdp        default  INGRESS    tcp:3389
sinter-p8-gateway-https  default  INGRESS    tcp:80,tcp:443
```

**確認できた事実はここまで**: VPC は `default` のみ、サブネットは `10.146.0.0/20`（asia-northeast1）、
**`default-allow-internal` という規則が VPC 内の tcp/udp 全ポート + icmp を許可する設定になっている。**

**この事実から先を事前に確定しない。**
Geneve(UDP 6081)・OVN Southbound(TCP 6642)・RabbitMQ(5672)・Keystone(5000)・Glance(9292)・Placement(8778) が
**実際に疎通するかどうかは、GCE での受入時に実測して確認する**（§5 区分 A の A7）。
規則の存在だけを根拠に「追加設定不要」と先に結論づけない。
ソースレンジ・ターゲットタグ・下位規則の優先度・OS 側のファイアウォールなど、
`list` の要約表示だけでは分からない要素が残っているため。

### 2.3 ネスト仮想化対応マシンタイプの実確認（読み取り専用）

```
$ gcloud compute instances create --help | grep nested
     --[no-]enable-nested-virtualization
        If set to true, enables nested virtualization for the instance.

$ gcloud compute machine-types list --zones=asia-northeast1-a \
    --filter="name~'^(n2|c3|n4d)-standard-(4|8|16)$'"
NAME            CPUS  MEMORY_GB  ZONE
n2-standard-4   4     16.00      asia-northeast1-a
n2-standard-8   8     32.00      asia-northeast1-a
n2-standard-16  16    64.00      asia-northeast1-a
```

- `--enable-nested-virtualization` フラグの存在を確認。
- **N2 は Intel Cascade Lake** であり、GCE の要件「Intel Haswell 以降」を満たす。
  E2 でもメモリ最適化でも Arm でも AMD でもないため、公式の除外リストに該当しない。
- `asia-northeast1-a` で `n2-standard-4 / 8 / 16` が利用可能。
- **ネスト仮想化が実際に効くかどうか（`/dev/kvm` が見えるか）は、受入時に実機で確認する。**

---

## 3. ローカルコンテナでの検証（必須・費用ゼロ）

### 3.1 確認すること（ホストを変更しない範囲）

| 分類 | 内容 |
|---|---|
| 構文 | `bash -n` が通る |
| 静的解析 | `shellcheck` が警告なしで通る |
| 設定生成 | `ini_set` の冪等性。生成された設定ファイルの内容が期待どおり。`tee -a` による重複追記が無い |
| 入力検査 | 想定外 OS / 必須項目の未指定 / 不正な NIC 名 / 不正な CIDR を**明確なエラーで拒否**する |
| 秘密情報 | 固定パスワードがソースに無い。生成物が 0600。`hagistack.env` / `secrets.env` が `.gitignore` 済み |
| **再実行時の安全性** | 2 回実行して DB 削除も設定重複も起きない。ソースに `DROP DATABASE` が無い |
| 制御構造 | サブコマンド解決、`usage()`、`set -euo pipefail` + `trap` による失敗時の明確な停止 |
| 危険な処理の不在 | AppArmor 無効化・libvirt の無認証 TCP 公開・MariaDB の 0.0.0.0 公開を行うコードが無い |

### 3.2 確認したことにしないこと

コンテナで通っても、以下は**実証扱いにしない**。

- `nova-compute` による **KVM ゲスト VM の起動**
- `/dev/kvm`・カーネルモジュール・libvirt の実挙動
- OVS / OVN のデータプレーン動作
- **物理 LAN の疎通**、provider network、Floating IP
- systemd ユニットの実起動順序と依存解決

> コンテナはホストのカーネルを共有し、特権なしでは `/dev/kvm`・ネットワーク名前空間・カーネルモジュールを
> 本番同等に扱えない。**コンテナでの合格をもって「OpenStack が動いた」とは書かない。**
> これらは GCE での受入（§5 区分 A・B）で確認する。

---

## 4. GCE での検証設計（必須・最大 2 台）

### 4.1 全体像

```
GCE node1 (n2-standard-8 相当, nested-virt ON)  ── 必須
┌──────────────────────────────────────────────────────────────┐
│ ens4 : 10.146.0.x/20  ← VPC。管理 LAN として使う             │
│         · API / RabbitMQ / OVN SB / Geneve(UDP 6081)         │
│         · 疎通は受入時に実測する（事前に確定しない）          │
│                                                              │
│ br-ex : 172.24.4.1/24  ← 【内部仮想 LAN】物理NICを入れない    │
│         · uplink を持たない OVS ブリッジ                      │
│         · ovn-bridge-mappings=physnet1:br-ex                  │
│         · ホストが provider GW 役 + iptables MASQUERADE       │
│                                                              │
│ public  = flat/physnet1/172.24.4.0/24/no-dhcp                │
│           FIP プール 172.24.4.100-200                        │
│ private = geneve/10.10.10.0/24 ── router r1 ── public        │
│                                                              │
│ Nova ゲスト(L2, KVM) ─ br-int ─ br-ex ─ ホストNAT ─ 外       │
└──────────────────────────────────────────────────────────────┘
                    │ Geneve over VPC (UDP 6081)
                    ▼
GCE node2 (n2-standard-4 相当, nested-virt ON) : compute-add ── 必須
   ens4 のみ。br-ex は持たない（N/S は node1 の gateway chassis 経由）
```

### 4.2 なぜ内部仮想 LAN にするのか

**GCE VPC は broadcast/multicast 非対応で、MAC/IP の照合も行われる。**
**したがって「VPC に 2 台つないだだけ」では provider network は成立しない。**
そこで **GCE VM のホスト内部に、物理 LAN の代わりとなる L2 セグメントを自前で作る**。

**この構成で確認できること** — Neutron の provider network のオブジェクトモデル、bridge mapping、
router の external gateway、Floating IP の払い出しと DNAT、SNAT、ゲスト→インターネット（二重 NAT）、
node1 ホストから FIP への到達、node2 のゲストが node1 の br-ex 経由で外へ出られること。

**この構成で確認できないこと** — §5 区分 C に列挙する。**物理 LAN 上の Floating IP はここには含まれない。**

### 4.3 Mac／UTM（任意）

| 項目 | 扱い |
|---|---|
| AIO 完走（arm64） | **任意**。できれば追加証跡として記録 |
| arm64 対応（`qemu-system-arm` 切り替え） | **任意**。初期の完了条件ではない |
| bridged NIC による**物理 LAN** provider network | **任意**。物理 LAN を試せる唯一の環境だが必須にしない |
| **物理 LAN 上の実 Floating IP** | **任意**。取れれば §5 区分 C から昇格させる |
| compute-add（2 ノード） | **任意**。GCE で必須確認するため |

**できなくても、実装も GCE 検証も止めない。** できなかった項目は区分 C に「未確認」として残す。

---

## 5. 受入結果の記録形式（3 区分に分離）

実装後、以下の 3 表を**別々に**埋める。**区分をまたいで「確認できた」と書かない。**

### 区分 A: GCE の 2 ノード間で確認したこと

| # | 確認項目 | 手段 | 結果 | 証跡 |
|---|---|---|---|---|
| A1 | node2 の `nova-compute` が controller から `up` に見える | `openstack compute service list` | | |
| A2 | node2 の OVN Controller が `Alive` | `openstack network agent list` | | |
| A3 | node2 の resource provider が生成される | `openstack resource provider list` | | |
| A4 | `cell_v2 discover_hosts` が自動実行され node2 が登録される | シェルのログ | | |
| A5 | **node2 を指定してゲスト VM を起動できる** | `--availability-zone nova:<node2>` | | |
| A6 | **node1 のゲストと node2 のゲストがテナント内で相互 ping**（= ノード間 Geneve 通信） | ゲスト内 `ping` | | |
| A7 | **ノード間の必要通信が実際に疎通する**（Geneve 6081 / OVN SB 6642 / RabbitMQ 5672 / Keystone 5000 / Glance 9292 / Placement 8778） | 受入時に実測。既存 FW 規則で足りたか、追加が要ったかを記録 | | |
| A8 | compute-add の再実行が安全 | 2 回実行 | | |

### 区分 B: GCE node1 の内部仮想 LAN 上で確認したこと

**node1 のホスト内部に閉じた `br-ex`(172.24.4.0/24)。物理 L2 ではない。**

| # | 確認項目 | 手段 | 結果 | 証跡 |
|---|---|---|---|---|
| B0 | all-in-one が 1 コマンドで完走する | シェルのログ | | |
| B1 | external provider network を flat/physnet1 で作成できる | `openstack network create --external --provider-network-type flat` | | |
| B2 | `ovn-bridge-mappings=physnet1:br-ex` が効いている | `ovs-vsctl` / agent ログ | | |
| B3 | router の external gateway を設定できる | `openstack router set r1 --external-gateway public` | | |
| B4 | **Nova でゲスト VM（cirros）が `ACTIVE` になる** | `openstack server list` | | |
| B5 | Floating IP を払い出して付与できる（DNAT） | `openstack floating ip create` / `server add floating ip` | | |
| B6 | **node1 ホストから FIP へ ping / SSH できる** | ホスト上で実行 | | |
| B7 | ゲスト VM から provider GW(172.24.4.1) へ ping | ゲスト内 | | |
| B8 | **ゲスト VM からインターネットへ ping**（ホスト MASQUERADE を挟む二重 NAT） | ゲスト内 `ping 8.8.8.8` | | |
| B9 | ゲスト VM で名前解決ができる | ゲスト内 `ping www.google.com` | | |
| B10 | cloud-init がメタデータを取得できている | `openstack console log show` | | |
| B11 | **Horizon** にログインでき、インスタンス一覧が見える | ブラウザ | | |
| B12 | node2 上のゲストが node1 の br-ex 経由で外に出られる（gateway chassis） | ゲスト内 | | |
| B13 | all-in-one の再実行が安全 | 2 回実行 | | |

**B 区分の但し書き（報告書に必ず併記する）**
> ここで確認した provider network / Floating IP は、**GCE VM のホスト内部に自前で作った仮想 L2 セグメント上での動作**である。
> GCE VPC は broadcast/multicast 非対応かつ MAC/IP 照合を行うため、VPC そのものを provider network として使うことはできない。
> **本区分の Floating IP が通っても、物理 LAN 上の Floating IP を検証済みとは書かない。**

### 区分 C: 物理 LAN では未確認のこと

**今回は未確認のまま残してよい。** Mac／UTM の任意検証で取れた項目だけ、証跡つきで昇格させる。

| # | 未確認項目 | なぜ未確認か | 確認するのに必要なもの |
|---|---|---|---|
| C1 | **物理 NIC を `br-ex` に収容する構成** | GCE では VPC の制約で不可。Mac は任意検証 | 物理 NIC 2 枚の実機、または Mac の bridged NIC |
| C2 | **物理 LAN 上の実 Floating IP**（OpenStack の外のマシンから到達） | 同上 | 同一 L2 の別マシン |
| C3 | 物理セグメント上の ARP 挙動 | 同上 | 実 LAN |
| C4 | **1 NIC 構成での管理 IP の `br-ex` 移設**（SSH 切断・再起動耐性） | GCE で実施すると SSH が切れて復旧手段を失うため実施しない | 物理コンソールを持つ実機、または Mac |
| C5 | 既存 LAN の DHCP / ルーターとの相互作用 | 事故になるため検証環境では実施しない | 隔離した実 LAN |
| C6 | **物理 VLAN**（provider VLAN セグメンテーション） | 初期スコープ外 | VLAN トランク対応スイッチ |
| C7 | 物理 x86_64 機での動作 | 検証環境が GCE(仮想) と Mac(arm64・任意) のみ | 物理 x86_64 サーバー |
| C8 | arm64（Mac／UTM）での AIO 完走と `qemu-system-arm` 切り替え | **任意検証のため**。必須受入から外した | Mac／UTM |
| C9 | **AWS EC2 上での動作一切** | **今回は調査のみ。操作しない**（§6） | — |

---

## 6. AWS EC2（調査のみ・操作しない）

**今回の範囲: 公式資料による調査と、候補・費用条件の整理まで。EC2 の起動・変更・動作確認は受入条件に含めない。**

### 6.1 公式資料から確認できた事実

出典: `docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html` および
`aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual`（**2026-02-16 発表**）

- **仮想（非ベアメタル）EC2 でネスト仮想化が可能**。Nitro が Intel VT-x を引き渡す（L0=Nitro / L1=EC2 / L2=ゲスト）。
- 対応インスタンスタイプ:
  - 汎用: `M7i` `M7i-flex` `M8i` `M8id` `M8i-flex`
  - コンピュート最適化: `C7i` `C7i-flex` `C8i` `C8id` `C8i-flex`
  - メモリ最適化: `R7i` `R7iz` `R8i` `R8id` `R8i-flex` `X8i`
  - ストレージ最適化: `I7i` `I7ie`
- **アーキテクチャ**: すべて Intel 系。**Graviton(Arm) は対象外**。
- **L1 ハイパーバイザ**: KVM と Hyper-V。
- **有効化**: `--cpu-options "NestedVirtualization=enabled"`（既存は停止後 `modify-instance-cpu-options`）。
- **追加料金なし**。全商用リージョン。
- 性能要件が厳しい場合は AWS 自身がベアメタルを推奨。
- ネットワーク: **ENI は promiscuous 非対応。Nitro が送信元/宛先 MAC を ENI 登録値と照合。**
  `source/dest check` の無効化は IP のチェックしか外さない。
  → **GCE と同様、VPC を物理 L2 provider network として使うことはできない。**

### 6.2 費用条件（AWS Price List Bulk API 実取得）

| 項目 | 内容 |
|---|---|
| 取得日時 | 2026-09-26 |
| 出典 | `AmazonEC2` publicationDate **2026-09-25T17:45:21Z** / `AWSDataTransfer` publicationDate **2026-09-16T13:22:08Z** |
| リージョン | **ap-northeast-1（東京）** |
| 課金条件 | オンデマンド / Shared / Linux / 事前導入ソフトなし / CapacityStatus=Used |
| 通貨 | USD（為替換算なし）。消費税・SP/RI 割引を含まない |

| タイプ | vCPU | メモリ | USD/時 |
|---|---|---|---|
| `m8i.xlarge` | 4 | 16 GiB | 0.27342 |
| `m8i.2xlarge` | 8 | 32 GiB | 0.54684 |
| `m8i.4xlarge` | 16 | 64 GiB | 1.09368 |
| `m7i.2xlarge` | 8 | 32 GiB | 0.52080 |
| `c8i.2xlarge` | 8 | 16 GiB | 0.47188 |
| `r8i.2xlarge` | 8 | 64 GiB | 0.67032 |

| 項目 | 単価 |
|---|---|
| EBS gp3 | 0.096 USD / GB-月 |
| gp3 追加 IOPS（3,000 超過分） | 0.006 USD / IOPS-月 |
| インターネット送信 0〜10TB/月 | 0.114 USD / GB |
| 無料枠 | 月 100 GB まで 0 USD |
| 受信 | 0 USD |

### 6.3 候補（将来 AWS で実施する場合の整理。今回は実施しない）

| 候補 | インスタンス | 台数 | ディスク | 稼働 | EC2 費用（概算） |
|---|---|---|---|---|---|
| 最小（AIO のみ） | `m8i.2xlarge` | 1 | gp3 100GB | 40h | 21.87 USD |
| 標準（AIO + compute-add を入れ子で 1 台に） | `m8i.4xlarge` | 1 | gp3 200GB | 40h | 43.75 USD |

EBS は停止中も課金される（例: 200GB を 7 日保持 ≈ 4.48 USD）。
実施する場合は、事前に当日の対応状況を実確認すること:
```
aws ec2 describe-instance-types --region ap-northeast-1 \
  --filters "Name=processor-info.supported-features,Values=nested-virtualization" \
  --query "InstanceTypes[].InstanceType" --output text
```
**（このコマンドも今回は実行していない。）**

---

## 7. GCE の費用

### 7.1 取得条件

| 項目 | 内容 |
|---|---|
| 取得日時 | **2026-09-26** |
| 出典 | **Google Cloud Billing Catalog API**（`cloudbilling.googleapis.com/v1/services/6F81-5844-456A/skus`）。利用者の既存 gcloud 認証トークンで読み取り（読み取り専用） |
| **SKU の effectiveTime** | **2026-09-26T07:00:00Z** |
| リージョン | **asia-northeast1（東京）** |
| 課金条件 | **OnDemand**。確約利用割引(CUD)なし。継続利用割引(SUD)は月間稼働率に応じて自動適用されるが、月 40 時間程度（稼働率約 5%）では実質的に効かない |
| 通貨 | USD。消費税を含まない |

### 7.2 確認済み単価（asia-northeast1 / OnDemand / effectiveTime 2026-09-26T07:00:00Z）

| SKU | 単価 |
|---|---|
| N2 Instance Core running in Japan | **0.040618 USD / vCPU-時** |
| N2 Instance Ram running in Japan | **0.005419 USD / GiB-時** |
| Balanced PD Capacity in Japan (`pd-balanced`) | **0.130 USD / GiB-月** |
| Storage PD Capacity in Japan (`pd-standard`) | 0.052 USD / GiB-月 |
| SSD backed PD Capacity in Japan (`pd-ssd`) | 0.221 USD / GiB-月 |
| Static Ip Charge in Japan | **0.015 USD / 時** |
| Network Internet Data Transfer Out: Japan → Americas / EMEA / Western Europe | 0.120 USD / GiB（10TiB 超で 0.085） |
| 同: Japan → Australia | 0.190 USD / GiB |
| 同: Japan → India | 0.140 USD / GiB |
| **同: Japan → APAC** | **カタログの `tieredRates` が空で読み取れなかった。** 日本国内からの接続はこの区分に当たるため、必要なら請求コンソールで確認すること |

### 7.3 マシンタイプ別の時間単価（上記 SKU からの算出）

| マシンタイプ | vCPU | メモリ | 計算 | USD/時 |
|---|---|---|---|---|
| `n2-standard-4` | 4 | 16 GiB | 4×0.040618 + 16×0.005419 | **0.249176** |
| `n2-standard-8` | 8 | 32 GiB | 8×0.040618 + 32×0.005419 | **0.498352** |
| `n2-standard-16` | 16 | 64 GiB | 16×0.040618 + 64×0.005419 | **0.996704** |

### 7.4 受入候補と**前提付き概算**

> **以下は確定請求額ではない。** 明示した前提のもとでの概算であり、
> 未算入・未確定の項目（§7.5）と価格変動によって実際の請求額は変わる。

**前提**

- node1 = `n2-standard-8`、node2 = `n2-standard-4`
- **各ノードの稼働時間 40 時間**（8 時間 × 5 日を想定）
- 各 `pd-balanced` **100 GB**、**ディスク保持 7 日**
- 外部 IPv4 を 2 個、各 40 時間
- リージョン asia-northeast1、OnDemand、CUD なし、SUD 実質なし、消費税別
- 単価は **effectiveTime 2026-09-26T07:00:00Z** のもの

| 内訳 | 計算 | USD |
|---|---|---|
| node1 コンピュート | 0.498352 × 40 h | 19.93 |
| node2 コンピュート | 0.249176 × 40 h | 9.97 |
| ディスク（100GB × 2 台、7 日保持） | 0.130 × 100 × 2 × (7/30) | 6.07 |
| 外部 IPv4（2 台 × 40 h） | 0.015 × 2 × 40 | 1.20 |
| **前提付き概算 合計** | | **≈ 37.2 USD** |

| 代替案（同じ前提） | 構成 | 概算 |
|---|---|---|
| AIO のみ（1 台） | `n2-standard-8` × 1、100GB、40h | ≈ 23.6 USD |
| 両方 8 vCPU | `n2-standard-8` × 2、100GB × 2、40h | ≈ 47.1 USD |

### 7.5 概算に**算入していない／確定していない**項目

| 項目 | 状況 |
|---|---|
| **通信料（下り）** | **未算入。** 日本国内からの接続に当たる「Japan → APAC」の単価をカタログから読み取れなかった（§7.2）。本用途の送信量は SSH と画面操作程度で小さいと見込まれるが、**確認していない** |
| **スナップショット** | **未算入。** 既存フリートに付いている `default-schedule-1` 相当のポリシーが Hagistack 用 VM にも付く場合、スナップショットのストレージ料金が別途かかる。create 時に付けない選択も検討する |
| **ディスクの停止中課金** | 概算には 7 日保持分を入れているが、**保持日数が延びればその分増える。** VM を停止してもディスクは課金され続ける |
| **稼働時間の超過** | 40 時間は想定値。構築のやり直しや調査で延びやすい |
| **価格変動** | 単価は 2026-09-26 時点。**Google はいつでも改定しうる。** 実施日に再取得すること |
| **イメージのライセンス** | Ubuntu（非 Pro）は追加ライセンス料なしと理解しているが、実施時に確認する |
| **ネットワーク関連の付帯費用** | Cloud NAT・ロードバランサ等は使わない前提。使うなら別途 |
| **消費税** | 含まない |

**費用を残さないための運用**
検証後は `destroy` でインスタンスとディスクを削除し、
`gce.sh status` と `gcloud compute disks list` で**残っていないことを確認する**（§9 Step 11）。
**ただし本書の作成時点では VM を一切操作していない。**

---

## 8. Sinter の GCE 接続シェルの確認結果と再利用計画

### 8.1 読んだもの（すべて読み取り専用・変更なし）

| ファイル | 行数 | 内容 |
|---|---|---|
| `/Volumes/VGX1000 SSD/Codex/Projects/sinter-acceptance/gce.sh` | 700 | GCE 受入ハーネス本体 |
| 同 `matrix.conf` | 40 | 宣言的ターゲット定義 |
| 同 `README.md` | 168 | アーキテクチャ・安全モデル・証跡レイアウト |
| 同 `scenarios/sinter/run.sh` | 319 | 製品固有シナリオ（VM 上で実行される側） |
| `Sinter/SINTER_CHATGPT_ACTION_DISCOVERY_REMEDIATION_REPORT.md` | — | GCE 運用の実例 |

**Sinter リポジトリへの変更は一切していない。** `gce.sh status`（read-only）のみ実行。

### 8.2 そのまま使える部分

`gce.sh` は製品非依存のライフサイクルコアとして書かれており、README に *"It knows nothing about Sinter."* と明記。
別製品はシナリオとアーティファクトを差し替えるだけで載る設計で、Hagistack はそれに当てはまる。

| 機能 | 再利用可否 |
|---|---|
| `matrix.conf` による宣言的ターゲット定義 | **そのまま**。行を足すだけ |
| `disposable=yes/no` ガード（`no` は create/destroy 不可） | **そのまま**。事故防止として重要 |
| `status`（厳密に読み取り専用のインベントリ） | **そのまま**。今回も実際に使った |
| `create`/`start`/`stop`/`destroy` とアイデンティティ検証（id + creationTimestamp の再確認、プレフィックス照合なし、境界つきポーリング、fail-closed） | **そのまま** |
| `run` の実行後 **自動 STOP**（`--keep-running` で抑止）、trap による EXIT/INT/TERM 時クリーンアップ | **そのまま**。従量課金の消し忘れ防止として価値が高い |
| アーティファクトの SHA-256 を**転送前後で検証** | **そのまま**。Hagistack のアーティファクトは `hagistack` シェル 1 ファイルなのでモデルが合う |
| 証跡レイアウト `evidence/<run-id>/<key>/{meta.env,scenario.log,scenario-out/}` | **そのまま**。§5 の 3 区分記録の土台になる |
| `run_env_prepare` の family ルーティング（fail-closed、製品失敗と区別して報告） | **そのまま**。debian 側の準備を挿す枠として使える |
| シークレット衛生（`.gitignore` で credentials/keys/known_hosts/evidence を除外） | **踏襲する** |

### 8.3 Hagistack のために足りないもの

| # | 不足 | 根拠 | 対応 |
|---|---|---|---|
| 1 | **`--enable-nested-virtualization` が無い** | `cmd_create` は `--machine-type` `--image-family` `--image-project` `--boot-disk-auto-delete` のみ | **必須**。無いと Nova の KVM ゲストが起動しない |
| 2 | **ブートディスクのサイズ/種別を指定できない** | 同上（既定 10GB） | **必須**。`--boot-disk-size=100GB --boot-disk-type=pd-balanced` 相当 |
| 3 | **`SCENARIO_TIMEOUT=1500`（25 分）** | 冒頭の定数 | **必須**。OpenStack AIO 構築は超える。5400 秒程度へ |
| 4 | **`run` は 1 ターゲットのみ** | `cmd_run` は *"run accepts exactly one target key"* | compute-add は 2 ノード協調が要る。**gce.sh のプリミティブを呼ぶ 2 ノード オーケストレータを上に被せる**。本体の単一ターゲット契約は壊さない |
| 5 | `PROJECT="sinter-508914"` がハードコード | 冒頭の定数 | 同じプロジェクトを使うなら変更不要 |
| 6 | ネットワーク/ファイアウォールの払い出しが無い | 設計上スコープ外 | §2.2 のとおり既存規則で足りる**見込み**。受入時に実測して判断する |

### 8.4 再利用計画（実装時。今回は作成しない）

**Sinter 側のリポジトリは変更しない。** 稼働中の別製品の受入基盤に Hagistack の都合を持ち込まない。

```
Hagistack/acceptance/            ← 新規（実装フェーズで作成）
├── gce.sh                       ← sinter-acceptance/gce.sh を出発点にコピーし §8.3 の 1〜4 を適用
├── matrix.conf                  ← Hagistack 用ターゲット
├── two-node.sh                  ← gce.sh のプリミティブを呼ぶ 2 ノード オーケストレータ
├── scenarios/
│   ├── allinone/run.sh          ← node1 で実行。§5 区分 B の項目
│   └── compute-add/run.sh       ← node2 で実行 + node1 側の discover_hosts。§5 区分 A の項目
└── evidence/                    ← .gitignore
```

matrix.conf（案）:

```
key | instance        | zone              | family | tier       | disposable | image                                 | machine       | nested
hs1 | hagistack-node1 | asia-northeast1-a | debian | disposable | yes        | ubuntu-os-cloud/ubuntu-2604-lts-amd64 | n2-standard-8 | yes
hs2 | hagistack-node2 | asia-northeast1-a | debian | disposable | yes        | ubuntu-os-cloud/ubuntu-2604-lts-amd64 | n2-standard-4 | yes
```

- 両方 `disposable=yes` にして、検証後に `destroy` で確実に消せるようにする
  （Sinter のフリートは `no` で保護されたまま影響を受けない）。
- `nested` 列を追加し、`create` で `--enable-nested-virtualization` に落とす。
- **`gce.sh status` は今すぐそのまま使える**ので、VM を作った後の在庫確認・消し忘れ確認に流用する。

---

## 9. 実施順

| Step | 場所 | 内容 | 費用 |
|---|---|---|---|
| 1 | **ローカルコンテナ** | `hagistack` の骨格 + preflight + 基盤 3 点。§3.1 の検査 | 0 |
| 2〜8 | **ローカルコンテナ** | Keystone → Glance+Placement → OVS/OVN/Neutron → Nova+cells v2 → 初期リソース → Horizon → `compute-add` の**設定生成と入力検査まで** | 0 |
| 9 | — | `Hagistack/acceptance/` を用意（§8.4） | 0 |
| 10 | **GCE node1** | create（nested-virt ON、100GB）→ **all-in-one の実受入** → **区分 B を埋める** → stop | 従量 |
| 11 | **GCE node2** | create → **compute-add の実受入** → **区分 A を埋める** → stop | 従量 |
| 12 | **GCE** | 両ノードを `destroy` し、**インスタンスとディスクが残っていないことを確認**（費用を残さない） | — |
| 13 | Mac／UTM（**任意**） | arm64 / 物理 LAN の追加検証。取れれば区分 C から昇格、取れなければ未確認のまま | 0 |
| 14 | — | 区分 A / B / C の 3 表を揃えて受入報告 | 0 |

**コンテナで通せるところは全部コンテナで通してから GCE に上がる。** GCE の稼働時間を最小にするため。
**AWS はこの順序に含まれない（調査のみ）。**

---

## 10. 本書で実行したコマンド（すべて読み取り専用・再現用）

```bash
# Sinter の GCE ハーネス（読むだけ。変更なし）
cat "…/sinter-acceptance/gce.sh" "…/sinter-acceptance/matrix.conf" \
    "…/sinter-acceptance/README.md" "…/sinter-acceptance/scenarios/sinter/run.sh"

# GCE 在庫（README に "strictly read-only" と明記のコマンド）
cd "…/sinter-acceptance" && ./gce.sh status

# GCE 環境の読み取り
gcloud compute networks list --project=sinter-508914
gcloud compute networks subnets list --project=sinter-508914 --filter="region:asia-northeast1"
gcloud compute firewall-rules list --project=sinter-508914
gcloud compute machine-types list --project=sinter-508914 --zones=asia-northeast1-a \
  --filter="name~'^(n2|c3|n4d)-standard-(4|8|16)$'"
gcloud compute instances create --help | grep -i nested

# GCE 料金（Billing Catalog API / 読み取り専用）
TOKEN=$(gcloud auth print-access-token)
curl -H "Authorization: Bearer $TOKEN" \
  "https://cloudbilling.googleapis.com/v1/services/6F81-5844-456A/skus?pageSize=5000"

# AWS 料金（公開エンドポイント・認証不要・読み取り専用）
curl "https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/region_index.json"
curl "https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSDataTransfer/current/region_index.json"
```

### 実行していないこと

- **GCE VM の作成・起動・変更・停止・削除**
- **OpenStack の導入**（構築コマンドを一度も実行していない）
- **AWS API の呼び出し**（認証不要の公開料金エンドポイントのみ。EC2 の起動も `describe-instance-types` も未実行）
- **Sinter リポジトリへの書き込み**
- **Hagistack の構築シェルの実装**（本書の作成時点では未着手）
