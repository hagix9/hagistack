# Hagistack

[English](README.md) | 日本語

Hagistack は、**Ubuntu Server 26.04 LTS** または **Rocky Linux 10.2** に
**OpenStack 2026.1（Gazpacho）** を導入するインストーラです。ディストリビューションごとに、
素の Bash で書いたスクリプトが 1 本あります。

## Hagistack とは

- **素の Bash で書いた OpenStack インストーラです。**
  構成管理エンジン、テンプレート、コンテナランタイムは使いません。
  使うのは Bash、`apt`/`dnf`、`systemctl`、OpenStack のコマンドラインツールだけです。
- **1 ディストリビューションにつき、インストーラは 1 本です。**
  対応プラットフォームごとに `hagistack` スクリプトが 1 本あり、次の決まった順序で phase を実行します。
  1. データベース
  2. メッセージキュー
  3. Keystone
  4. Glance
  5. Placement
  6. OVN
  7. Neutron
  8. Nova
  9. Horizon
  10. 初期リソース
- **実行する前に読めるように書いています。**
  各手順がなぜ必要かはコメントで説明しています。
  運用者は phase を順に追って、マシンに何が変更されるかを確認できます。
- **意図的に小さく保っています。**
  Hagistack は OpenStack-Ansible、Kolla-Ansible、Packstack、DevStack のいずれでもありません。
  それらのプロジェクトは、複数ノードのオーケストレーション、コンテナ化されたサービス、
  開発環境など、別の課題を解いています。
  Hagistack が目指すのは、動く all-in-one ノードと追加のコンピュートノードまでを、
  短く、直接読める経路で導入することです。

## 対応プラットフォーム

| | Ubuntu Server 26.04 LTS | Rocky Linux 10.2 |
|---|---|---|
| アーキテクチャ | amd64（検証済み）。arm64 は preflight を通過しますが**未検証**です | x86_64 のみ（それ以外は拒否されます） |
| OpenStack | 2026.1 Gazpacho | 2026.1 Gazpacho |
| パッケージの入手元 | Ubuntu 26.04 の公式アーカイブ | **先に自分でビルドする** RPM。`build-rpms.sh` で、固定した 2026.1 リリース tarball からビルドします |
| 検証 | Google Compute Engine 上の 2 ノード、2026-09-28 | Google Compute Engine 上の 2 ノード、2026-09-29 |

上記以外の OS バージョンは、preflight で拒否されます。

例外が 1 つあります。Rocky 用スクリプトは、他の EL10 系ディストリビューション
（RHEL、AlmaLinux、CentOS 10）では警告を出して処理を続けます。これらは未検証です。

## バージョン方針

Hagistack は、Git HEAD や未検証の「最新」には追従しません。
対象 OS の最新版と OpenStack の最新の安定リリースを検証し、検証済みのバージョンを
**Current Generation** として**固定（pin）**します。Current Generation とは、
「対応プラットフォーム」に載せた OS と OpenStack の組み合わせで、CI と実 OS での受け入れを通過したものです。
バージョン、ソースリリース、packaging の commit、SHA-256 などの pin により、
Current Generation は再現可能に保たれます。
「最新に追従する」とは、新しいリリースを把握して検証することです。
ビルドのたびに最新を取得するという意味ではありません。

- **OS の新しい minor リリース**（例: Rocky 10.2 → 10.3）は候補として扱います。
  新 OS で Current Generation を検証し、必要なら最小限の互換修正を行い、
  受け入れと独立監査を通過した後に Current Generation を更新します。
  OS の更新と OpenStack の更新は、可能な限り同時に行いません。
- **OpenStack の新しい安定リリース**も候補として扱います。
  manifest と pin は明示的に更新し、ブランチへの追従では更新しません。
  release candidate や未リリースの開発コードは Current Generation にしません。
- **Rocky と Ubuntu では供給方式が異なります。** Rocky では、固定した upstream リリースと
  固定した packaging ソースから Hagistack がパッケージをビルドし、RDO の packaging テキストは
  同梱しません。Ubuntu では、サポート対象の Ubuntu アーカイブのパッケージを使います。
  upstream の fix は自動では取り込まないため、サポート対象の Ubuntu パッケージに
  反映されるまで作業を保留（HOLD）する場合があります。
- **Legacy。** 以前に検証した generation は、新しい Current Generation に置き換わった時点で
  *Legacy* になります。コードやドキュメントが残り、今も動く可能性はありますが、
  継続的な CI、実 OS での受け入れ、セキュリティ修正の backport、
  新しい依存や新しい OS 環境との互換性は保証しません。

coding agent 向けの規則を含む方針の全文は [docs/CURRENT_GENERATION_POLICY.md](docs/CURRENT_GENERATION_POLICY.md) にあります。

## プラットフォームを選ぶ

- **[Ubuntu Server 26.04 LTS →](ubuntu26.04/README.ja.md)**
  パッケージは Ubuntu の公式アーカイブから入れます。事前のビルドは不要です。
- **[Rocky Linux 10.2 →](rocky10.2/README.ja.md)**
  OpenStack 2026.1 の EL10 向けパッケージはどこも公開していません。
  **インストールの前に、OpenStack の RPM リポジトリを自分でビルドする必要があります。**

## クイックスタート

1. **プラットフォームを選び**、そのガイドを開きます（上のリンク）。
2. **ホストを準備します。** 次のものが必要です。
   - 対応 OS をクリーンインストールしたマシン
   - `sudo` による root 権限
   - provider NIC として指定する、実在するインターフェース
   - provider ネットワークの値（CIDR、ゲートウェイ、Floating IP の範囲）

   Rocky の場合は、ビルド済みの RPM リポジトリも必要です。
3. **preflight だけを実行します。**
   `sudo ./hagistack all-in-one --check …`
   すべての設定を検証し、最終的な設定値を表示します。何も変更しません。
4. **インストールします。** `sudo ./hagistack all-in-one …`

   コンピュートノードを追加する手順は次のとおりです。
   1. コントローラで `compute-secrets` を実行します。
   2. 新しいノードで `compute-add` を実行します。
   3. コントローラに戻って `discover-hosts` を実行します。
5. **確認します。** `sudo ./hagistack status` を実行し、各プラットフォームのガイドに従ってテスト用ゲストを起動します。

正確なコマンドとオプションは、各プラットフォームのガイドにあります。

## インストールされるもの

all-in-one（コントローラ兼コンピュート）ノードには、次のものが入ります。

| コンポーネント | 内容 |
|---|---|
| Keystone | Identity API（ポート 5000）。Web サーバの mod_wsgi で動作します |
| Glance | Image API（ポート 9292） |
| Placement | Placement API（ポート 8778） |
| Nova | Compute API（8774）とメタデータ API（8775）、conductor、scheduler、compute。compute は libvirt の KVM を使い、`/dev/kvm` が使えない場合は QEMU を使います。cells v2（`cell0` と `cell1`） |
| Neutron | Networking API（ポート 9696）。ML2/OVN ドライバと OVN メタデータエージェントを使います |
| Open vSwitch / OVN | コントローラには OVN の northbound/southbound データベースと `ovn-northd`、各ノードには `ovn-controller` が入ります。ノード間は Geneve トンネルで結びます |
| Horizon | ポート 80 のダッシュボード。Ubuntu では `/horizon`、Rocky では `/dashboard` |
| MariaDB | `127.0.0.1` だけで待ち受けます |
| RabbitMQ | ユーザーは `openstack` の 1 つだけです |
| memcached | 管理 IP で待ち受けます |

あわせて、次の初期リソースを作成します。

- フレーバー `m1.tiny`
- ダイジェストを検証した CirrOS 0.6.3 イメージ
- ネットワーク `hagistack-provider`（flat、external）と `hagistack-tenant`（Geneve）
- ルータ `hagistack-router`
- admin プロジェクトの `default` セキュリティグループに追加する ICMP と SSH のルール
- キーペア `hagistack-key`

`compute-add` で追加したコンピュートノードには、`nova-compute`、libvirt、Open vSwitch、
`ovn-controller`、OVN メタデータエージェントが入ります。

**含まれないもの**
- Cinder（ブロックストレージ）、Swift、および上に挙げていない OpenStack サービス
- noVNC コンソールプロキシ

## コマンド

サブコマンドとオプションは、表中で区別している箇所を除き、両プラットフォームで同じです。

| コマンド | 実行場所 | 内容 |
|---|---|---|
| `all-in-one [options]` | コントローラ | このホストにコントローラとコンピュートのサービスを導入します |
| `all-in-one --check [options]` | コントローラ | preflight だけを行います。設定を検証して最終的な設定値を表示し、何も変更しません |
| `compute-add --controller-ip IP [options]` | 新しいノード | このホストを追加のコンピュートノードにします |
| `compute-secrets` | コントローラ | コンピュートノードに必要な 5 つの資格情報を標準出力に書き出します。端末への出力は拒否します |
| `discover-hosts` | コントローラ | 新しく登録されたコンピュートホストを Nova の cell に登録します |
| `status` | 任意のノード | バージョン、phase の完了マーカー、サービスの状態を表示します |
| `--help`、`--version` | — | 使い方の説明とバージョン文字列を表示します |

- **Rocky のみ：** `all-in-one` と `compute-add` には `--repo-url` も必要です。自分でビルドした RPM リポジトリを指定します。
- **終了ステータス：**
  - `0`：成功です。
  - `1`：設定または preflight のエラーです。
  - `2`：使い方の誤りです。
  - `4`：最後まで実行しましたが、1 つ以上の phase をスキップしたため、導入は**未完了**です。
  - それ以外の非ゼロ値は、あるコマンドが失敗して実行が止まったことを示します。

## 検証状況

Google Compute Engine 上で**検証済み**です。仮想マシンはネスト仮想化を有効にしており、
`virt_type=kvm` で動作しました。各プラットフォームで、all-in-one ノード 1 台と、
追加したコンピュートノード 1 台を使いました。

| | Ubuntu 26.04（2026-09-28） | Rocky 10.2（2026-09-29） |
|---|---|---|
| `all-in-one` がスキップした phase なしで完了する | ✓ | ✓ |
| Keystone、Glance、Placement、Neutron、Nova への認証付き呼び出し | ✓ | ✓ |
| 2 台目のノードで `compute-add` を実行し、両方のハイパーバイザが登録されて cell に割り当てられる | ✓ | ✓ |
| 両方のノードでゲストが ACTIVE になる | ✓ | ✓ |
| ゲスト内で cloud-init が完了する（メタデータサービスを利用し、SSH 鍵が注入される） | ✓ | ✓ |
| 別々のノード上のゲスト同士が ping で通信でき、その通信を Geneve トンネル上で捕捉した | ✓ | ✓ |
| 2 回目の実行では何も変わらない（終了コード 0、どの unit も再起動しない） | ✓ | ✓ |
| Horizon への admin サインイン。ログインページが 200 を返すだけでなく、認証済みのセッションを確認した | ✓（同日 1 回目の実行。最終修正の前） | ✓ |

**実装済みだが未検証のもの**
- Ubuntu の arm64 での動作
- Rocky 用スクリプトを他の EL10 系で動かすこと
- ホストファイアウォールが有効なホスト
- 3 台以上の構成

**対象外、または含まれないもの：** 「既知の制約」を参照してください。

## 既知の制約

**含まれないもの**
- **provider NIC の接続。** Hagistack は **provider NIC を provider ブリッジ（`br-ex`）に接続しません**。
  指定した NIC が存在することは確認しますが、ブリッジには物理ポートを付けません。
  自分で NIC を接続するまで、provider ネットワークと Floating IP は物理 LAN に到達しません。
- **上に挙げたもの以外のサービス。** Cinder（ボリューム）、Swift などのサービスは導入しません。
- **noVNC。** コンソールプロキシを導入しないため、Horizon のコンソールタブは使えません。
- **ファイアウォール。** ホストファイアウォールの設定は行いません。

**未検証のもの**
- 物理 LAN を経由する provider 経路と、ホストの外から Floating IP に到達すること
- ライブマイグレーション
- 3 台以上の構成
- Ubuntu の arm64
- Rocky での SELinux enforcing モード。Rocky は SELinux を **permissive** にした状態でのみ検証しており、
  インストーラ自身がホストを permissive に切り替えます（Rocky のガイドを参照してください）。
- RPM の `%check` テストスイート。Rocky の RPM は `--nocheck` でビルドしています。

**サポート外のもの**
- 上に挙げた以外の OS バージョンや OpenStack リリース
- x86_64 以外のホストでの Rocky

## 安全性に関する性質

以下はコードとそのテストで確認できる性質です。

- **固定パスワードはありません。**
  すべての資格情報は初回実行時に生成され、`/etc/hagistack/secrets.env`（mode `0600`）に書き込まれます。
  以後の実行ではそのまま再利用するため、再実行しても稼働中のパスワードが変わることはありません。
- **設定ファイルは解析するだけで、実行しません。**
  受け付けるのは既知のキーの `KEY=VALUE` 行だけです。
  値に使える文字は、英字、数字と `. _ - : / @ + =` だけです。
- **データベースを削除することはありません。**
  データベースとユーザーは、存在しない場合にだけ作成します。
- **コンピュートノードに渡すものは最小限です。**
  `compute-secrets` が渡すのは、ちょうど 5 つの資格情報です。
  データベースのパスワードや admin のパスワードがコンピュートノードに渡ることはありません。
- **再実行を前提に設計しています。**
  - 設定はキー単位で編集します。
  - 初期リソースは名前で確認し、なければ作成します。
  - 検証済みのホストでの 2 回目の実行は、終了コード 0 で、何も再起動しませんでした。
  - 失敗した実行は**ロールバックしません**。原因を直してから、同じコマンドをもう一度実行してください。
- **未完了の実行は、未完了だと報告します。**
  依存先のサービスに到達できずに phase をスキップした場合、終了コードは `0` ではなく `4` になります。
- **ノードは信頼できる管理ネットワークに置いてください。**
  API、RabbitMQ、OVN southbound データベース、memcached は管理ネットワーク上で待ち受け、
  Hagistack はファイアウォールのルールを追加しません。

## リポジトリの構成

```text
README.md, README.ja.md     このページ
docs/                       Current Generation の方針（バージョン方針と coding agent 向けの規則）
LICENSE                     Hagistack 自身のコードの MIT License（下の「ライセンス」を参照）
ubuntu26.04/                Ubuntu Server 26.04 用インストーラ、テスト、検証記録
acceptance/                 日付つきの受け入れ・調査の記録
rocky10.2/                  Rocky Linux 10.2 用インストーラ、RPM ビルドツール、spec の調整ルール
rocky10.2/third-party/      独自のライセンスを持つ第三者のファイル（Neutron の patch、Apache-2.0）
```

## 歴史

- **2012 年：** CentOS 6 に OpenStack を導入するシェルスクリプト群「centstack」として始まり、
  まもなく Hagistack に改名しました。
- **2012〜2013 年：** CentOS 6 と Ubuntu 12.04〜13.10 の上で、
  Essex から Havana までの OpenStack に追従しました。
- **2014 年：** Ansible 版を別のリポジトリに分離しました。
- **2026 年：** OpenStack 2026.1 向けの素の Bash インストーラとして、一から書き直しました。

2012〜2013 年のスクリプトは 2026 年に作業ツリーから削除しましたが、Git の履歴には残っています。

## ライセンス

現在のツリーにある Hagistack 自身のコードとドキュメントは、[MIT License](LICENSE) で提供します。
Copyright (c) 2026 Shiro Hagihara。

第三者のものは、それぞれのライセンスのままです。

- `rocky10.2/third-party/neutron/` には、Apache License 2.0 の OpenStack Neutron の patch が 2 つあります。
  これらは MIT License の**対象外**です。ライセンス全文、上流の帰属表示、元のコミットは
  同じディレクトリ（`LICENSE`、`NOTICE.md`）にあります。
- `acceptance/` の記録にある上流 OpenStack のコミット ID と件名や、`ubuntu26.04/` の記録にある設定の抜粋など、
  他のプロジェクトからの引用は、元のライセンスのままです。
- このスクリプトが導入またはビルドするソフトウェア（OpenStack、RDO のパッケージング、Python パッケージなど）は、
  このリポジトリには含まれません。実行時に取得するもので、それぞれのライセンスに従います。

MIT License が対象とするのは、現在のツリーのファイルです。Git の履歴にある過去のリビジョンの条件について
述べるものではありません。
