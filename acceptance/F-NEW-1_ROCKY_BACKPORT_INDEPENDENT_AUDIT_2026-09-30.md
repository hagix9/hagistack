# Rocky F-NEW-1 独立監査 — 2026-09-30

判定: **INCONCLUSIVE（証拠不足による停止）**。製品欠陥の再現や修正不一致を認定したものではありません。依頼 §12/15/40 が要求する SRPM を含む正確なビルド来歴を、保存された証拠から確立できませんでした。§44 の「exact RPM provenance cannot be established」に従い、実行時監査を含む残りの監査を停止しました。

未確認の PASS/YES/NO を発行しません。以下の「未検証」は失敗の再現を意味せず、停止後に未実施の項目です。実装報告の結論は採用していません。

## A. AUDIT PREFLIGHT

対象リポジトリ: `/Volumes/VGX1000 SSD/Codex/Projects/Hagistack`。開始時のチャット作業ディレクトリは Sinter でしたが、別リポジトリであることを remote から確認し、Hagistack に移動しました。

`git fetch origin` 成功。

- branch: `fix/rocky-neutron-maintenance-lock`
- HEAD: `207795084855e0fa7e3bce7124d4f0440408cfd4`
- origin/master: `7a20dbe1ba8cde14f9e35252e1f9074387d695d6`
- ahead/behind: `4 / 0`
- tracked modifications: 0
- staged files: 0
- 初期 untracked: `AGENTS.md`、`acceptance/F-NEW-1_OVN_MAINTENANCE_LOCK_INVESTIGATION_2026-09-30.md`、`acceptance/F-NEW-1_UPSTREAM_BACKPORT_FEASIBILITY_2026-09-30.md`
- 対象2コミットを直接指すタグ: なし

Git オブジェクトから確認した祖先:

```
207795084855e0fa7e3bce7124d4f0440408cfd4 40472e879bf55d66fb4f3ecb719d67fb180567d6 docs: record Rocky maintenance lock acceptance
40472e879bf55d66fb4f3ecb719d67fb180567d6 2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f fix: backport Neutron maintenance lock fix on Rocky
2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f cb3154a361f343b940fffaa6bdbc0f5a7aad234e docs: record WP-A acceptance evidence
cb3154a361f343b940fffaa6bdbc0f5a7aad234e 7a20dbe1ba8cde14f9e35252e1f9074387d695d6 fix: run required Neutron workers
7a20dbe1ba8cde14f9e35252e1f9074387d695d6 c7a15d5a60d0fd753f9c3a93afc606b657ce9bd0 23473ae41fe2ee0713ac3eca2ed5940e2c0c26ca Merge pull request #5 from hagix9/docs/modernize-readme
```

## B. AUDITED OBJECTS

製品:

```
40472e879bf55d66fb4f3ecb719d67fb180567d6
2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f
dbb2b2f1ad1dc41650a278467f20653d422966bf
fix: backport Neutron maintenance lock fix on Rocky
```

証拠:

```
207795084855e0fa7e3bce7124d4f0440408cfd4
40472e879bf55d66fb4f3ecb719d67fb180567d6
9f5c17357de6464b0e957bec5b35189e28f91262
docs: record Rocky maintenance lock acceptance
```

製品で変更されたパスは C の5パスだけ。証拠コミットの変更は `acceptance/F-NEW-1_ROCKY_BACKPORT_ACCEPTANCE_2026-09-30.md` の追加だけです。指定された SHA と親は一致しました。tree は上記の実測値を記録しています（依頼に比較対象の tree 値はありません）。

Git オブジェクトの SHA-256:

| パス | SHA-256 |
|---|---|
| `rocky10.2/spec-patches/neutron.patch` | `d3755588c744d756218e5b673dff1a33aa943000769c31b373ffd91d58073098` |
| `rocky10.2/gazpacho.manifest` | `8c22a5bdc7d4302a0084f661b9c09b68d9d47b21dc99be2b64ecb700de813538` |
| `rocky10.2/tests-neutron-maintenance-lock.py` | `b8ae2d4997feffb8c887e59b07617bad060e2ce4aec98ce1ad6a60c7bee89793` |
| `rocky10.2/README.md` | `871a927db12f4e57ad8ed2eb515f03187b9bbe3b29bf6028bd32198898710030` |
| `rocky10.2/README.ja.md` | `c17a71ac2df51cd88d1eca492e55205312cbbaaeb0fb2652cbe006273e1bab43` |
| `rocky10.2/hagistack` | `082a4a8c3879fedd1b0db262cea83fa39c63d7e4edba2536959f1e58c453e170` |
| `rocky10.2/build-rpms.sh` | `1ad25aa87a0279358576109377a2665f12e3cd5f8d0761d8f577ef8fe4362754` |

証拠文書: SHA-256 `abb496425e698922f2a5bbb423afe577cc55f55789ea836f2e80224a5ace14a5`、380行。独立した実装最終報告の全文・文書ハッシュは依頼に提示されていないため、その報告との一致は未検証です。

## C. PRODUCT SCOPE

`PRODUCT DIFF SCOPE: CLEAN`

`2556d832..40472e8` の全差分を列挙しました。

| パス | 分類 |
|---|---|
| rocky10.2/spec-patches/neutron.patch | A: 2つのバックポートを生成する diff、Patch0001/0002 宣言、説明。既存2つの %files 修正は内容不変、行番号のみ移動 |
| rocky10.2/gazpacho.manifest | B: neutron 行の Release 1 → 2 の1トークン |
| rocky10.2/tests-neutron-maintenance-lock.py | C: 明示実行する回帰テストの追加 |
| rocky10.2/README.md | D: 上流2コミット、Release 2、テストの説明1段落 |
| rocky10.2/README.ja.md | D: 同上 |

これはパス・hunk の用途の確認であり、パッチの意味的等価性の認定ではありません。

## D. UBUNTU IMMUTABILITY

`UBUNTU PRODUCT CHANGES: ZERO`

Ubuntu、トップレベル README、日本語 README、共有ビルド・テスト基盤に差分はありません。全変更パスが C に限定されていることによって確認しました。

## E. UPSTREAM IDENTITY

監査専用 bare clone を外部 SSD に作成し、`https://opendev.org/openstack/neutron.git` から両方の完全 SHA を fetch しました。実装が保存したコピーだけに依存せず、上流 remote で完全 SHA の存在を確認しました。記録したオブジェクト:

```
83f1d8305651a0ab23629c88d70bfa237055158c
Parent: c695003d1012b911aa7c3f604d6d169d2567521c
Tree: aa795a7b61bb8e986454e92b0a319cd26db97e47
Author: Terry Wilson <twilson@redhat.com>
Author date: 2026-06-09T17:33:16-05:00
Subject: Ensure MaintenanceWorker lock set before connect
The Idl.set_lock() call sets the lock name on the Idl class and
sends a request to ovsdb-server requesting a lock. It does not
wait for a reply. This creates a window where we run without
yet receiving the lock, and tasks might fire and fail and have
to be retried.

If set_lock() is called prior to connection, the reply that
contains the initial database dump wil aslo have the reply to the
set_lock request, so we eliminate that window.

Related-Bug: #2155155
Change-Id: Iaefe1e2cc86ddd55c9053fde66353b2a333e1e98
Signed-off-by: Terry Wilson <twilson@redhat.com>

Paths:
neutron/common/ovn/constants.py
neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py
neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py
git show SHA-256: 097d61274b0f1c7cbba244cbe07fa764926167305ca3a1e9d1fb1a241e5748ed
Stable patch-id: d4f005b5e1a08395fa097c92c6f6250b4ac25963 83f1d8305651a0ab23629c88d70bfa237055158c

91abb5e720e1c515dbfbe9b2313fbdff92b2abbf
Parent: 319761f0697026227aa7b0a882bfdfddbae74f91
Tree: 657e22bdefc7ea3cba3ab007e395c6fcb303f522
Author: Terry Wilson <twilson@redhat.com>
Author date: 2026-06-17T18:45:25-05:00
Subject: Only set the maintenance worker lock on the worker
Other code passes the MaintenanceWorker as the trigger to
from_server() like the ovn-db-sync-util and only the real
MaintenanceWorker itself should call set_lock() before
connecting.

Closes-Bug: #2156979

Signed-off-by: Terry Wilson <twilson@redhat.com>
Change-Id: I74145ef1407856b7ec75de87daa2270b452b6c70

Paths:
neutron/plugins/ml2/drivers/ovn/mech_driver/mech_driver.py
neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py
git show SHA-256: 83c796609f37ba9674f2d4f9dbb2a577012c9a5d82dbdf1606ae7918b8ca9f84
Stable patch-id: 69cb7daa4df255c68d582a921aa53da8730511f6 91abb5e720e1c515dbfbe9b2313fbdff92b2abbf```

完全な patch 出力は監査専用ディレクトリに保存しています。

## F. TWO-COMMIT DEPENDENCY

`TWO-COMMIT DEPENDENCY: NOT VERIFIED`

候補に埋め込まれたパッチでは、0001 が MaintenanceWorker/RpcWorker の共有分岐に定数の set_lock を追加し、0002 が worker_class.lock_name の有無で制限することを読み取りました。ただし正確な 28.0.2 と stable/2026.1 の独立再構築は停止前に完了していません。

## G. LOCAL PATCH PROVENANCE

`LOCAL BACKPORT PROVENANCE: NOT VERIFIED`

2つの完全 upstream SHA、author/date、Change-Id、cherry-picked 行、適用順序を候補の Git オブジェクトで確認しました。独立 cherry-pick と format-patch の byte 比較は未実施です。

## H. PATCH EQUIVALENCE

未検証。`ROCKY BACKPORT MATCHES MINIMAL UPSTREAM FIX: YES` は発行しません。完全な affected files の独立比較を実施する前に停止しました。

## I. EXCLUDED CHANGES

未検証。候補の差分には c695003d/a8feb94e のパッチ追加はありませんが、構築後の完全なソースと RPM 内での除外を独立認定していません。

## J. SOURCE / RELEASE IDENTITY

`NEUTRON SOURCE VERSION CHANGED: NO`

`NEUTRON RPM RELEASE: 2`（候補 manifest の値。RPM header の独立確認は未実施）

- source version: 28.0.2
- source tarball: neutron-28.0.2.tar.gz
- manifest SHA-256 pin: `cdaf45a2100de5233e4c1cc7c01c9df2b634510a0f0436913f73f29d42d325ee`
- distgit pin: `fa1f5135e66282364250f2f5630a48423f497099`
- 前の Release: 1、候補: 2

manifest の変更は Release のみ。tarball 実体の独立取得・hash 検証は未実施です。

## K. BUILD CHAIN

**確立できず。ここが停止点です。**

候補 build-rpms.sh は親から不変です。候補 Git オブジェクトから以下を確認しました:

1. pinned distgit をコピーする。
2. `patch -p1 --dry-run` 後に spec-patches/neutron.patch を適用する。
3. spec を SPECS にコピーし Version/Release を置換する。
4. distgit の `.spec` と `.git` 以外の全ファイルを SOURCES にコピーする。新規 patch ファイルもこの経路に入る。
5. `rpmbuild -br --nodeps` で build requirements を生成する（`.buildreqs.nosrc.rpm` は削除する）。
6. 本ビルドは `rpmbuild -bb $checkflag "$spec"`。通常の SRPM を作る `-bs`/`-ba` はこの経路にありません。

保存された raw/builder/build-neutron.log には wrapper の成功表示があり、`raw/builder/neutron-rpmbuild-log.sha256` に完全ログのハッシュを記録しています。しかし、候補ビルドの完全な neutron.rpmbuild.log 自体は見つかりませんでした。保存された digest は次です:

```
c3808f3954ed4957d2815dad48f0ee5331770cdb8cbf65711e621260617634d2  /home/a0000/epoxy-build/logs/neutron.rpmbuild.log
```

指定 raw evidence、前段 backport evidence、WP-A evidence の各ディレクトリを読み取り検索しました。`.src.rpm` は見つからず、完全 neutron.rpmbuild.log は旧 WP-A のものだけでした。旧 Release 1 のログで候補 Release 2 を証明することはできません。

候補の served-repo-fix.tar の member を独立列挙すると、RPM 196、Neutron 28.0.2 の binary RPM 15、SRPM 0 でした。served repo に SRPM を公開しないこと自体は正常ですが、別途保存された SRPM とその hash もありません。

証拠文書 §7 と inventory の `openstack-neutron-28.0.2-2.el10.src.rpm` は binary header の SOURCERPM 名を示します。この文字列は実在する SRPM の生成・保存・内容・hash を証明しません。証拠が捏造されたとは判断していませんが、要求された `Git → patch → spec → SRPM → binary RPM` の連鎖は未証明です。

## L. RPM INVENTORY

tar member の数は上記のとおり独立確認しました。15 binary RPM の Name/Epoch/Version/Release/Arch/header digest/payload digest は raw inventory に存在しますが、その値はまだ RPM 自体から独立再計算していません。したがって実装の hash table を独立測定値として転載しません。

## M. RPM CONTENT

未検証。保存されている rpm-content-verification.txt と sha256 リストは実装側の出力であり、独立抽出の代わりにはしていません。

## N. BUILD VARIANCE

pbr.json、sample config の #my_ip、F13b の分類は未検証。停止により payload 比較を実施していません。

## O. REGRESSION TEST AUDIT

候補の全テストコードを読みました。real neutron の from_worker と DBInconsistenciesPeriodics を import し、private ovsdb-server を起動します。python-ovs の private lock request method に 20ms sleep を挿入します。mock.MagicMock の OVN client を使い、MaintenanceWorker.lock_name はテスト自身が設定します。そのため post_fork_initialize の実行は試験していません。

PASS 条件は3回の NB write 成功・stuck 不成立、RPC lock 不要求、A所有/B待機と A終了後B所有です。handover 後の guarded write や B待機中の guarded write 抑止は直接実行して確認していません。これは試験範囲の制限であり、候補欠陥の認定ではありません。

## P. NEGATIVE CONTROL

未検証。実装の regression-results.txt は patched PASS / unpatched FAIL を記録していますが、独立実行は未実施です。`F-NEW-1 REGRESSION NEGATIVE CONTROL: PASS` は発行しません。

## Q. RPC SAFETY

未検証。8 session / zero lock の raw summary は存在しますが、pcap と PID/port 対応を独立再構築していません。

## R. LOCK HANDOVER

未検証。raw test は所有権移動のみを記録します。依頼された待機中/引き継ぎ後の guarded work を含む独立認定は未実施です。

## S. DEPLOYED PRODUCT IDENTITY

候補 hagistack の完全 hash は B に記録しました。両ノードの raw hash との独立突合は停止により未完了です。

## T. DEPLOYED RPM IDENTITY

未検証。installed-vs-repo.txt の MATCH 行は存在しますが、RPM headers と installed rpmdb 記録を独立再照合していません。バージョン一致を byte identity と扱っていません。

## U. REPOSITORY / CLIFF

repo の RPM 数196のみ独立確認済み。181 unchanged、DNF provider selection、EPEL cliff の正確な identity、substitution の適否は未検証です。

## V. REAL ROCKY ACCEPTANCE

未検証。サービス、API、ゲスト、metadata、Geneve、ログについて独立 PASS を発行しません。

## W. START TRIALS

未検証。42/42 を独立認定していません。trials-R/S.tsv、trials-wire.tsv、pcap、reboot 記録は存在しますが、trial count と interval の突合は未実施です。

## X. EXTERNAL NUDGE

未検証。全試験証拠からの nudge 不使用の独立確認は未実施です。

## Y. IDEMPOTENCY

未検証。before/after snapshots は存在しますが、独立比較は停止により未実施です。

## Z. SECURITY

未検証。停止前に読んだ製品差分・証拠文書には明白な秘密を認識していませんが、全追加内容の系統的スキャンは未完了です。`TRACKED SECRET MATERIAL ADDED: NO` を認定しません。

## AA. DEFERRED ITEMS

`O-A: DEFERRED`

`TAG_REQUEST FINDING: DEFERRED`

`F13b: DEFERRED`

`UBUNTU F-NEW-1: UNFIXED / HOLD`

これらは依頼の判定境界です。今回の証拠不足は deferred defect の修正を要求するものではありません。Ubuntu に変更がないことは独立確認済みです。

## AB. FINDINGS

### IA-01 — HIGH — exact RPM build provenance の証拠不足

- Description: 要求された候補 SRPM と hash、および候補の完全 rpmbuild ログを保存された証拠から取得できません。SOURCERPM 名とログ digest だけでは内容を監査できません。
- Evidence: K、候補 build-rpms.sh の `-br`/`-bb`、raw/builder の保存ファイル、tar member 一覧、関連 evidence directory の read-only 検索。
- Impact: acceptance standard §40(12) の正確なビルド来歴を独立確立できません。root fix の誤りを示すものではありません。
- Blocking: **YES**。
- Stop rule: §44「exact RPM provenance cannot be established」。
- Re-audit に必要な証拠: 当該ビルドの SRPM と完全 SHA-256、および対応する完全 rpmbuild log/保存 SOURCES・spec を、当時の binary RPM に結びつける記録。将来の新規ビルドだけでは当時の artifact identity の証明になりません。

修復・再ビルド・証拠書き換えは行っていません。

## AC. CLOUD CLEANUP

この独立監査ではクラウドの作成・開始・停止・削除・変更を行っていません。監査作成リソースは0。実装の delete.log は存在しますが、クラウド現在状態の独立照会は未実施です。既存・無関係なリソースには触れていません。

監査専用ローカル資料は `/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-independent-audit-2026-09-30/` に保存し、人手レビュー用に残します。実装の raw evidence は変更・削除していません。

## AD. MUTATION SUMMARY

`AUDIT PRODUCT MUTATIONS: ZERO`

- tracked modifications: 0
- staged files: 0
- commits: 0
- pushes: 0
- PRs: 0
- tags/releases: 0
- Git metadata: 指示された origin fetch に伴う FETCH_HEAD/remote refs の更新のみ
- 新規 untracked file: この報告書だけ
- outside repo: 監査専用 bare clone、upstream patch bytes、preflight metadata

## AE. VERDICT

ROCKY F-NEW-1 ROOT FIX: INDEPENDENT AUDIT INCONCLUSIVE
UBUNTU WP-A STATUS: HOLD
WP-A MERGE: HOLD
HAGISTACK ROCKY F-NEW-1 BACKPORT AUDIT: INCONCLUSIVE
