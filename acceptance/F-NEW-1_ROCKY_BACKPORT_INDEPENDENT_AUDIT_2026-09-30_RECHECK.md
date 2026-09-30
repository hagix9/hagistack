# Rocky F-NEW-1 独立監査 再確認 — 2026-09-30

判定 INCONCLUSIVE。ビルド来歴の証拠不足という停止条件を独立に確認したため、残りは未検証です。既存監査書の結論を根拠にはしていません。

## A. AUDIT PREFLIGHT

git fetch origin 成功。branch: fix/rocky-neutron-maintenance-lock。HEAD: 207795084855e0fa7e3bce7124d4f0440408cfd4。origin/master: 7a20dbe1ba8cde14f9e35252e1f9074387d695d6。ahead/behind: 4/0。tracked/staged 変更0。開始時 untracked は AGENTS.md、調査書、feasibility 書、既存独立監査書の4件。既存監査書は上書きしていません。

## B. AUDITED OBJECTS

207795084855e0fa7e3bce7124d4f0440408cfd4 40472e879bf55d66fb4f3ecb719d67fb180567d6 9f5c17357de6464b0e957bec5b35189e28f91262 docs: record Rocky maintenance lock acceptance
40472e879bf55d66fb4f3ecb719d67fb180567d6 2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f dbb2b2f1ad1dc41650a278467f20653d422966bf fix: backport Neutron maintenance lock fix on Rocky
2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f cb3154a361f343b940fffaa6bdbc0f5a7aad234e 83ef40df9b1b9656abc496711153192cf8138f17 docs: record WP-A acceptance evidence
cb3154a361f343b940fffaa6bdbc0f5a7aad234e 7a20dbe1ba8cde14f9e35252e1f9074387d695d6 a3e16307dfe5bff1500cf9b7056ac8ff304d8a76 fix: run required Neutron workers
7a20dbe1ba8cde14f9e35252e1f9074387d695d6 c7a15d5a60d0fd753f9c3a93afc606b657ce9bd0 23473ae41fe2ee0713ac3eca2ed5940e2c0c26ca 4f723322c7f0d3315965d8b6ceab703e73a04d8e Merge pull request #5 from hagix9/docs/modernize-readme


## C. PRODUCT SCOPE

PRODUCT DIFF SCOPE: CLEAN

全差分は rocky10.2/spec-patches/neutron.patch（A: 上流バックポート）、gazpacho.manifest（B: Release）、tests-neutron-maintenance-lock.py（C: 回帰テスト）、README.md と README.ja.md（D: 説明）の5パス。hunk の用途は確認済み、意味的等価性は未認定。

## D. UBUNTU IMMUTABILITY

UBUNTU PRODUCT CHANGES: ZERO

全変更パスの列挙により Ubuntu・トップレベルREADME・共有基盤に変更がないことを確認。

## E. UPSTREAM IDENTITY

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## F. TWO-COMMIT DEPENDENCY

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## G. LOCAL PATCH PROVENANCE

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## H. PATCH EQUIVALENCE

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## I. EXCLUDED CHANGES

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## J. SOURCE / RELEASE IDENTITY

NEUTRON SOURCE VERSION CHANGED: NO
NEUTRON RPM RELEASE: 2

候補manifest値: 28.0.2、neutron-28.0.2.tar.gz、SHA-256 cdaf45a2100de5233e4c1cc7c01c9df2b634510a0f0436913f73f29d42d325ee。distgit fa1f5135e66282364250f2f5630a48423f497099。変更はNeutron Release 1→2だけ。RPM header は未独立検証。

## K. BUILD CHAIN

停止点。候補 build-rpms.sh の実ビルドは rpmbuild -bb（行346）、buildreq生成は -br（行328）。通常SRPM生成の -bs/-ba はありません。SOURCERPM名はSRPM実体の証明になりません。

指定raw領域の build-neutron.log はwrapper出力。完全ログはhash c3808f3954ed4957d2815dad48f0ee5331770cdb8cbf65711e621260617634d2 と当時のbuilderパスだけが保存されています。外部SSDの Codex/tmp 全域を読み取り検索（.git/node_modules除外）して、Neutron .src.rpm は0、完全 neutron.rpmbuild.log は旧 hagistack-wpa-remediation-2026-09-30/raw/builder の1件だけでした。

served-repo-fix.tarを展開せずmember列挙: RPM196、Neutron28.0.2-2 binary15、SRPM0。公開repoにSRPMがないこと自体は欠陥ではありません。しかし要求された Git→spec/SOURCES→SRPM→binary の正確な連鎖は保存証拠から確立できません。

## L. RPM INVENTORY

独立確認はtar内のRPM196・候補Neutron15・SRPM0の件数まで。header/payload/NEVRA/hashの独立再計算は停止により未実施。

## M. RPM CONTENT

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## N. BUILD VARIANCE

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## O. REGRESSION TEST AUDIT

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## P. NEGATIVE CONTROL

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## Q. RPC SAFETY

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## R. LOCK HANDOVER

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## S. DEPLOYED PRODUCT IDENTITY

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## T. DEPLOYED RPM IDENTITY

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## U. REPOSITORY / CLIFF

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## V. REAL ROCKY ACCEPTANCE

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## W. START TRIALS

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## X. EXTERNAL NUDGE

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## Y. IDEMPOTENCY

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## Z. SECURITY

未検証。§44の停止条件により実施していません。PASS/YES/NOは認定しません。

## AA. DEFERRED ITEMS

O-A: DEFERRED
TAG_REQUEST FINDING: DEFERRED
F13b: DEFERRED
UBUNTU F-NEW-1: UNFIXED / HOLD

## AB. FINDINGS

IA-R01 / HIGH / Blocking YES。候補SRPMの実体・hashと完全rpmbuildログが保存証拠に見当たらず、要求された正確なRPMビルド来歴を確立できない。根拠はK。影響: acceptance §40(12)を満たせず、§44 exact RPM provenance cannot be established により停止。製品欠陥や証拠捏造の認定ではありません。再監査には当時のSRPM、完全ログ、spec/SOURCESとbinaryへの対応記録が必要。再ビルドや証拠の書き換えはしていません。

## AC. CLOUD CLEANUP

クラウド操作0、監査作成リソース0。既存リソース・実装raw evidenceには触れていません。

## AD. MUTATION SUMMARY

AUDIT PRODUCT MUTATIONS: ZERO

tracked変更0、staged0、commit0、push0、PR0、tag/release0。origin fetchと新規untracked報告書のみ。既存報告書は変更していません。

## AE. VERDICT

ROCKY F-NEW-1 ROOT FIX: INDEPENDENT AUDIT INCONCLUSIVE
UBUNTU WP-A STATUS: HOLD
WP-A MERGE: HOLD
HAGISTACK ROCKY F-NEW-1 BACKPORT AUDIT: INCONCLUSIVE

Gitオブジェクトの独立SHA-256:

- 40472e8:rocky10.2/spec-patches/neutron.patch: d3755588c744d756218e5b673dff1a33aa943000769c31b373ffd91d58073098 (214行)
- 40472e8:rocky10.2/gazpacho.manifest: 8c22a5bdc7d4302a0084f661b9c09b68d9d47b21dc99be2b64ecb700de813538 (155行)
- 40472e8:rocky10.2/tests-neutron-maintenance-lock.py: b8ae2d4997feffb8c887e59b07617bad060e2ce4aec98ce1ad6a60c7bee89793 (165行)
- 40472e8:rocky10.2/README.md: 871a927db12f4e57ad8ed2eb515f03187b9bbe3b29bf6028bd32198898710030 (640行)
- 40472e8:rocky10.2/README.ja.md: c17a71ac2df51cd88d1eca492e55205312cbbaaeb0fb2652cbe006273e1bab43 (601行)
- 40472e8:rocky10.2/build-rpms.sh: 1ad25aa87a0279358576109377a2665f12e3cd5f8d0761d8f577ef8fe4362754 (479行)
- 2077950:acceptance/F-NEW-1_ROCKY_BACKPORT_ACCEPTANCE_2026-09-30.md: abb496425e698922f2a5bbb423afe577cc55f55789ea836f2e80224a5ace14a5 (380行)
