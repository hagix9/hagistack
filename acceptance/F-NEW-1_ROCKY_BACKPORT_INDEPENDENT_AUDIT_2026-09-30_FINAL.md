# Rocky F-NEW-1 PATH-B Independent Audit — 2026-09-30

判定: **INCONCLUSIVE**。NEW artifactのビルド来歴・spec/patch/source identityは独立に確立でき、前回の来歴blockerはNEW setについて解消しました。しかしhandoverのguarded work実行と、critical runtimeログの保存範囲がPASS standardを満たしません。§43に従い停止し、未完了項目をPASSにしていません。製品欠陥や証拠捏造を認定したものではありません。

監査対象は凍結Git objectとNEW PATH-B実体。旧artifactをretroactively検証していません。新しいruntime環境・試験は実行していません。既存runtime evidenceの独立内容監査です。

## A. Preflight

`PRODUCT CANDIDATE 40472e8: UNCHANGED`

- branch: fix/rocky-neutron-maintenance-lock
- HEAD: 207795084855e0fa7e3bce7124d4f0440408cfd4
- origin/master: 7a20dbe1ba8cde14f9e35252e1f9074387d695d6
- ahead/behind: 4/0
- tracked変更・staged: 0
- 開始時untracked: AGENTS.md、INVESTIGATION、FEASIBILITY、既存INDEPENDENT_AUDIT、RECHECK、RPM_PROVENANCE_REMEDIATIONの6件。

Gitオブジェクトの親・tree:

```text
Product 40472e879bf55d66fb4f3ecb719d67fb180567d6
Parent  2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f
Tree    dbb2b2f1ad1dc41650a278467f20653d422966bf
Evidence 207795084855e0fa7e3bce7124d4f0440408cfd4
Parent   40472e879bf55d66fb4f3ecb719d67fb180567d6
Tree     9f5c17357de6464b0e957bec5b35189e28f91262
```

祖先は 7a20dbe1 → cb3154a3 → 2556d832 → 40472e87 → 20779508。前回のGit検証をそのままPASSとして継承せず、今回も状態・差分を再確認しました。

## B. Previous audit blocker

`PREVIOUS AUDIT BLOCKER: RPM PROVENANCE EVIDENCE`

前回RECHECKのIA-R01は候補SRPM・完全rpmbuildログの不足でした。修正の誤りを発見した監査ではありません。前回独立に成立していたのはコミット・祖先、5パスの用途限定、Ubuntu不変、manifestのRelease変更、保存tarの件数です。上流等価性・runtime PASSは未成立でした。今回、新ビルドの来歴を独立に確認しましたが、後述のruntime証拠不足が残ります。

## C. PATH-A review

`PATH A RECOVERY: NOT POSSIBLE FROM PRESERVED EVIDENCE`

前回の検索および候補build-rpms.shの確認により、通常ビルドは-br/-bbのみで-bs/-baを実行しません。旧Release 2の完全ログはdigestのみ、完全な旧Release 1ログは別物です。元builder削除は実装証拠のcleanup記録によるもので、今回クラウド履歴を照会していません。PATH Bの実体はPATH Aの歴史的証明になりません。

## D. Old/new separation

`OLD/NEW ARTIFACT SETS: CLEANLY SEPARATED`

旧artifact表はremediation §D、新artifact表は§Lで分離。新binaryは全15件が旧SHA-256と異なります。今回の32-start、deployment、build transcriptはhgprov-*用だけを扱い、旧42-startは新RPMの証明に使っていません。

## E. Product mutation

`PATH-B PRODUCT MUTATIONS: ZERO`

`UBUNTU PRODUCT CHANGES: ZERO`

git diff 40472e8 -- . ':!acceptance' は空。tracked working/staged変更も空。製品コミットの5パスとRelease 1→2の範囲は不変です。

## F. Build graph

`PATH-B BUILD GRAPH REPRESENTED ACCURATELY: YES`（実行グラフ）

```text
40472e8 + pinned distgit/tarball → staged SPECS/SOURCES
                                ├─ rpmbuild -bs → frozen SRPM
                                └─ rpmbuild -bb → frozen binary RPMs
```

shimは-brをexecで通し、-bbを受けると入力hash→-bs→SRPMコピー→入力hash→実/usr/bin/rpmbuild -bbを行います。binaryをSRPMファイルからrebuildしていません。

報告§Sの表には「SRPM → frozen 15 binary RPMs」という不正確な行見出しがあります。直後の本文はmechanically derived from SRPMを明示否定しているため、証拠全体を偽ったとは判断しませんが、行見出しはLOWの証拠表現finding（PB-03）。本監査は上記の実グラフだけを認定します。

## G. Candidate inputs

`PATH-B BUILD INPUTS MATCH 40472e8: YES`

Gitオブジェクトのneutron.patchから新規2patchを生成し、公式rdo-packages/neutron-distgitの完全SHA fa1f5135e66282364250f2f5630a48423f497099 を外部SSDの監査専用bare repositoryへfetchして独立適用しました。源tarballはSRPMから独立抽出し、SHA-256 cdaf45a2100de5233e4c1cc7c01c9df2b634510a0f0436913f73f29d42d325ee = manifest pin。Version 28.0.2、Release 2、distgit pinは不変です。

公式 https://opendev.org/openstack/neutron.git から83f1d8305651a0ab23629c88d70bfa237055158c と91abb5e720e1c515dbfbe9b2313fbdff92b2abbfを今回fetchしました。保存された実装コピーだけに依存していません。

上流0001はlock設定をconnectionより前に移し、28.0.2のMaintenanceWorker/RpcWorker共通分岐では0001単独でRPCにもlock設定する。0002はpost_fork_initializeでMaintenanceWorkerだけにlock_nameを設定し、from_workerでlock_nameがないクラスはAttributeErrorでスキップ。正確な28.0.2のsource traceから二つを併用する理由を確認しました。

## H. -bs / -bb input equivalence

`-bs AND -bb INPUT EQUIVALENCE: VERIFIED`

inputs-before-bs.sha256 と inputs-after-bs.sha256は完全一致。独立抽出SRPM全29memberのhashは対応するSPECS/SOURCESのpre-bs値と一致。-bs終了から-bb開始までshimに入力変更の命令はありません。inputs-after-bbとの差はneutron-destroy-patch-ports.serviceの1件だけで、%prepに明示されたsedに対応します。これを入力が最初から違ったことや再現性の証明とは扱いません。

## I. Build transcript

`COMPLETE PATH-B RPMBUILD TRANSCRIPT: VERIFIED`

stage.shは開始・command・PATHを記録し、stdout/stderrを2>&1でteeし、PIPESTATUS[0]を保存。build-rpms.shによる別ファイルへの出力もneutron.rpmbuild.logとして保存されています。

build.transcript開始12:21:57.189Z、shim -bs 12:23:17.870Z、SRPM freeze12:23:18.666Z、-bb開始12:23:18.668Z、-bb exit=0 12:24:26.097Z。stage終了12:24:48.407Z。26,086行のログに%prep/%generate_buildrequires/%build/%install、両patch全affected filesのapply、15 Wrote行、clean処理あり。%checkは明示--nocheck。SRPM生成は12:23:18.529Zにexit=0。

SHA-256は証拠SHA256SUMSの235件すべてについて再計算し一致、欠落0。

- build.transcript: 8f123bb8d3a77c8cf0d1785a7cad40b71840cb8a905b9550b8519e1d2ee2504a
- build.raw: d3b7438e8d072fed03232cad9b2ec4f04288b693bb761f0e592e34e96e48b448
- neutron.rpmbuild.log: fa297077675730d1958b75a0cc32c239dfb8aa5f9a9d75d9371bc9d3b9cf2790
- rpmbuild-bs.log: 0d8568bf957c84b104eb0ddcff821b29888141845f208cd0d28f9e20734e679f

hash一致は内容の正しさの代わりにはしていません。spec/patch/payloadは別途独立比較済み。

## J. SRPM

`PATH-B SRPM IDENTITY: VERIFIED`

`SRPM SPEC MATCHES EXPECTED CANDIDATE SPEC: YES`

`SRPM PATCH0001 MATCHES CANDIDATE: YES`

`SRPM PATCH0002 MATCHES CANDIDATE: YES`

/usr/bin/bsdtarで独立抽出。specはpinned distgit＋候補patch＋候補build-rpms.shに実装されたVersion/Release/signing key/autosetupの4変換から導出。完全bytes一致、SHA-256 ad1584f0be1a162d63d318f629a10d76c15e656d8a7216c543ba4f64e14dd72f。Patch宣言は0001/0002だけ。

0001: 4f981103be17689f9186776b5059c55bb33950dae47740fd52575be7849387e4

0002: 136ce37c86bf3ac8dd7f737b23c5e2b60bdb17326cac6876852ebc4bfb96d9cf

独立SRPM metadata/hashはLに記載。freeze marker12:31:19Z/ledger12:31:22Zはtarget creation12:31:49Zより前。独立の第三者timestamp署名はありませんが、保存されたbuild/deploymentの時系列に矛盾はありません。

## K. Binary provenance

`PATH-B BINARY RPM PROVENANCE: VERIFIED`

候補から独立導出されたspec/patch → 保存staged hash → wrapperが同specのreal -bbを実行 → 完全ログに15出力 → 各RPMのfile/header/payload hash → frozen inventory の一致を確認。SRPMの存在だけでbinary来歴を認定していません。前回のIA-R01は**新artifact setに限って解消**。旧artifact setはprovenance-incompleteのままです。

## L. RPM inventory

`PATH-B RPM INVENTORY FROZEN BEFORE DEPLOYMENT: YES`

独立にRPMヘッダーをbig-endian index/storeとして解析し、signature headerのSHA256HEADERとmain header bytesのSHA-256、およびPAYLOADDIGESTとcompressed payload bytesのSHA-256を再計算しました。16/16一致。binary15件はneutron-rpm-inventory.tsvの全Name/Epoch/Version/Release/Arch/size/file hash/header/payloadと一致。全binary Epoch=1、Version=28.0.2、Release=2.el10、Arch=noarch、SOURCERPM=openstack-neutron-28.0.2-2.el10.src.rpm。SRPMのheader arch=noarchはsrc filenameと区別します。

| File | NEVRA（header） | size | SHA-256 | SHA256HEADER | PAYLOADDIGEST | SOURCERPM |
|---|---|---:|---|---|---|---|
| openstack-neutron-28.0.2-2.el10.noarch.rpm | openstack-neutron-1:28.0.2-2.el10.noarch | 32659 | e5761d6a6b4998140b521aa9ea1b570e6ee5c04ca1a1ff0e832222e6846581d3 | 8b2353bd9a435c8462dba9f585c59b4784527cce638caad12b85c2e1f4df2c8a | 00a8bbe5e8066d28103bae667e77c18b05ec6de3ca3ac77fc467a006af264989 | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-common-28.0.2-2.el10.noarch.rpm | openstack-neutron-common-1:28.0.2-2.el10.noarch | 156655 | 83472f0e8a73f1d8b811518a01f5d69fc1332ff64fc077a12bfaf992aa7bcc93 | e4b2213e12493d0fa22b65f2110832dda7559626701435d19b92af7b3431dd6e | 1bb44f09d212b58f6617dfa9c161f8b33ef63159a21e012b32f1f4669672a73c | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-macvtap-agent-28.0.2-2.el10.noarch.rpm | openstack-neutron-macvtap-agent-1:28.0.2-2.el10.noarch | 12955 | 5a6d567cace934d819b19b6d6d2585092d1fc1e8658ed9b6946b0ec1157d500a | 7def88870d8afaba62de91a0e142e4a46fd07b71ff103dec762fbcb6de58c1c1 | d489e81de288e10e8c0d5d90b71635e52bdbab3a99aded1ffe4293e3e4666374 | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-metering-agent-28.0.2-2.el10.noarch.rpm | openstack-neutron-metering-agent-1:28.0.2-2.el10.noarch | 16476 | f11b5b01bb772d93c97ec18f35eb344ea48ecdda9aff9f0dd60bdbb5c56a3a1d | 5060645129aefa1cdd2e5d67ba9dea367468f3f5b30a04a76f5049ea80324742 | f86c0a87d2c39c45d36a3b01c0d0cfe1f4f5913092eec4abd710491b19f04810 | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-ml2-28.0.2-2.el10.noarch.rpm | openstack-neutron-ml2-1:28.0.2-2.el10.noarch | 22584 | 282c938f9f503ed33bb9ce2c3b7d2979d09229111af3049ec1251869e32385d5 | 71f9fb4fcc7ce73971e7840cba695f85b4b609678a1230f408ce9e28b88eb4ea | 303421595af5e239020eecb624bd05d6ce631508cab04e9f1cddd049de184b9b | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-ml2ovn-trace-28.0.2-2.el10.noarch.rpm | openstack-neutron-ml2ovn-trace-1:28.0.2-2.el10.noarch | 11075 | 344bbeaec6f3bb8f5f18e61848608f502f32f8b1747072e0a8e981028b297d07 | ca08985cfc3397d698402a2268a1d15a0dbb7fd5558d0d71f0b1dd009b050a9b | 597ee3f96485302ee8b163fc7bb172900cd8b793478755c8655383cb0bf97125 | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-openvswitch-28.0.2-2.el10.noarch.rpm | openstack-neutron-openvswitch-1:28.0.2-2.el10.noarch | 21394 | db193750395c8c47d1e87ba3f431e448353e34c620b00c835dd2566144a97898 | a3e4d8306fface0cafe484ecebf7e3d2ff1e5d7bb5f49d26736fedda554491ef | 64ba24954131d8b65763042aca8ce38a24e6fc426d70b34bed8a9dbe3ac9256d | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-ovn-agent-28.0.2-2.el10.noarch.rpm | openstack-neutron-ovn-agent-1:28.0.2-2.el10.noarch | 19030 | 1284fada0975f88f7ebefcf6b7a765d1825697c2a5501c31c9c848cce7b26a5e | 74d51627f56724c470e85cc5a9dcf5a3eada375b873bdfe08045d7820b539dd8 | c09c6f68fcb82129240ee25d2c69d6d8dfa844037968935c0eb8c0b5ed96acc9 | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-ovn-maintenance-worker-28.0.2-2.el10.noarch.rpm | openstack-neutron-ovn-maintenance-worker-1:28.0.2-2.el10.noarch | 12499 | e0012bdd042228118289e2426577bac456d99efa0b7cd37af894c2553140e4ac | 838756770805abcf16cd9167f6f9b0b57024028845bfdbf1df71e66ca1dde332 | e5fb1d8e78162008be2b5fca239d2dd1dd7e0f2e0dc374b816eb7190bee8110f | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-ovn-metadata-agent-28.0.2-2.el10.noarch.rpm | openstack-neutron-ovn-metadata-agent-1:28.0.2-2.el10.noarch | 17193 | e6df9ba5ade1eb9c94aec4ec93bdbc7737e047dbe760f1d721f7b952ce226aff | 9f05afab9e5186a524b4968ac3bd4d64b319df326f0baf93e72edb5503ce7225 | 9ffc921fd6e9c773e2aac0ddd80db10b40b3e9225bb7e4ae165f2a8685a5764b | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-periodic-workers-28.0.2-2.el10.noarch.rpm | openstack-neutron-periodic-workers-1:28.0.2-2.el10.noarch | 12404 | 691b4f97460fe366823e97d72b45bd846cb2a783c327f067f8c0d4771aee9f24 | 1b82bd5609168057af122ba306f6222125b41d8f39062704370a6ad7efd56081 | 5ae699ede67f401d77f82813aaa9f521ae229921fcd287ae113b0cd4c801e61f | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-rpc-server-28.0.2-2.el10.noarch.rpm | openstack-neutron-rpc-server-1:28.0.2-2.el10.noarch | 12055 | 08cd4918bf94d500761d95e5ce27f215456255fc22cb0ebfaed902148c0e4f01 | 763138e2002a42269318abef68f40b1e9a49bb73baaffbd5fe24632a44fb908d | 3ec401bb526583e119e821466848d71f18b4f680ff8f7e7217cc3b4a87939cdb | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-sriov-nic-agent-28.0.2-2.el10.noarch.rpm | openstack-neutron-sriov-nic-agent-1:28.0.2-2.el10.noarch | 16291 | 589142edad6fc34b93597810406c5d3f52ba65c360e2a694f073eca573ea6c81 | 9df96131aa6ac2057977fbb5ce0b6fe4e2da32447dafd35d34d9074871bcdfe6 | a5da44d67cf4b1957355cde12240a918d89ab8ee70317ba1b768d9f649d6d0e0 | openstack-neutron-28.0.2-2.el10.src.rpm |
| python3-neutron-28.0.2-2.el10.noarch.rpm | python3-neutron-1:28.0.2-2.el10.noarch | 3450580 | 1afd65940e98a29c2fb7c74b6daaa2a54185c9a80a1de7362e63c04228a94307 | b06a3b71f3b8a85a2cb6913df42881b6ea2a12be9d7faf8d76b444139658bace | 7b8d4ee0b653f076e54058113a12247689524221c5210a7f7fdeb1fcc80e00e9 | openstack-neutron-28.0.2-2.el10.src.rpm |
| python3-neutron-tests-28.0.2-2.el10.noarch.rpm | python3-neutron-tests-1:28.0.2-2.el10.noarch | 4331861 | d2edd6da8722f5ae6dd4c186bb7d93b31ba7ec10f9c5a0ded87bf2ef23485aaa | 3d2059e33188a2d0107c5584a27e8c9d0105fa96e6ecb302bef4dc9391497750 | c3d713004ae7c8fcf888124bff7852624469663cdb1ec5c25fda30d80d528c69 | openstack-neutron-28.0.2-2.el10.src.rpm |
| openstack-neutron-28.0.2-2.el10.src.rpm | openstack-neutron-1:28.0.2-2.el10.noarch | 12424560 | 47f8cd8e7421b064fdf4ca4f15e5854917a92e01103a38cffd1bd5998f4a012c | 2f01f4956100441f04c3bff69bf84eb0a2e98435c737465f83bb92c08212a68c | e40bb820f745b9275389d095a83d9a0a9214563e2f55135854edce8ee80d1a17 | なし（SRPM） |


## M. RPM content

`PATH-B PATCHED RPM FILES MATCH UPSTREAM PAIR: YES`

`OPTIONAL HAS_LOCK COMMIT INCLUDED: NO`

`TAG_REQUEST FIX INCLUDED: NO`

二つの独立treeをSRPM内28.0.2から作成。Aは候補から生成したpatchを適用、Bは公式Git objectのdiffを適用。上流のMaintenanceWorker単独分岐contextは28.0.2のMaintenanceWorker/RpcWorker共有分岐へ**context行だけ**適応し、追加・削除行は変更していません。上流原文とcontext適応版を両方保存。候補tree・上流pair tree・新python3-neutronから独立抽出した完全4ファイルがbyte-identical。

| File | SHA-256 |
|---|---|
| neutron/common/ovn/constants.py | 9083ce4a0a00d6dd8fdbfb3f555590bcb5e5694c9df347e749651ee789dbd675 |
| neutron/plugins/ml2/drivers/ovn/mech_driver/mech_driver.py | d0dda5739ceca47561a0a7b7e90f7b35610fe08ffcbc36faac16d2fc10ca9d48 |
| neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py | 06d9c453ab6f83efa81069b5cef9beae8345867ab31cbd1e302de362cd35d9ae |
| neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py | d3e16686e6cb625c2464498ed780a334cba87b540e304af83cbc13f439081cb0 |

候補の変更はpairのdiffだけ。第三patchやmasterファイル丸ごとの取り込みはありません。

## N. python333 finding

`PYTHON333 FINDING: PRE-EXISTING / F13b-FAMILY / NON-BLOCKING`

独立抽出SRPM: ExecStart=/usr/bin/python333。新openstack-neutron-openvswitch binary: /usr/bin/python3333。pinned specはSOURCESの/usr/bin/python文字列を/usr/bin/python3へin-place sed。shimに-brが3回あり、元python→python3→python33→python333、その後-bb %prepでpython3333となる。pre/post入力hashの差はこのfileだけ。

このsedはpinned specにあり、製品候補で追加されていません。maintenance-workerは別unit/entrypointで、このdestroy-patch-ports.serviceを使いません。PATH-Bのlock挙動を説明する変更ではありません。旧RPM familyに同じ値があるという実装の全3build比較は、本監査では独立再抽出していません。今回独立成立したのはpinned spec由来・候補以前のmutation mechanismと新SRPM/binaryの値です。F13bを修復せず、reproducibleとは呼びません。

## O. Reproducibility language

`UNSUPPORTED REPRODUCIBILITY CLAIMS: NONE`

報告はreproducible buildを明示否定し、新RPM全15hashが旧と違うことを記載しています。spec byte-identicalという限定的主張はJで確認。§SのSRPM→binary行見出しはF/PB-03のLOW表現findingとして別扱い。pbr.json/sample configのbuild varianceは今回停止前に独立比較を完了していません。

## P. Repository

`PATH-B VALIDATION REPOSITORY: VERIFIED`（保存bundleの構成・新Neutron identity）

tar memberを独立読取: binary RPM196、旧Neutron28.0.2-1は0、新15件はfrozen RPM full SHA-256と全一致。repomd.xml SHA-256 cd0990867f8100b0205667a9d2f828f736a3dc64fb5de38391dcfa3562ee240a。pre-installのfreeze list照合・installed from_repoは新bundle使用を支持します。全repodata内部チェックサム・181 unchangedの再比較は停止前に未完了のため、repoの全属性を包括PASSとは認定しません。

## Q. Deployed identity

`PATH-B DEPLOYED HAGISTACK MATCHES 40472e8: YES`

`PATH-B DEPLOYED NEUTRON RPMS MATCH FROZEN INVENTORY: YES`

候補hagistack SHA-256 082a4a8c3879fedd1b0db262cea83fa39c63d7e4edba2536959f1e58c453e170 はrocky1-final/rocky2-after-caddのfull hashに一致。

独立再計算したRPM header/payload digestと、nodeの実query記録を直接照合: controller8 Neutron packages、compute3 packagesが一致。worker/common/python3-neutronのcritical identitiesを含みます。controllerのworker/periodic/python3-neutron rpm -V rc=0も記録。Version equalityだけには依存していません。

ident.pyはDNF from_repo対象をNEVRAでinventoryに結び、SHA256HEADERとPAYLOADDIGESTを両方比較。controller104/104・compute70/70の記録あり。ただし全installed raw query行が保存されていないため、この2つの全package件数は再集計していません。Neutronのdirect raw header行を根拠に限定的YESとし、全104/70を独立再計算したとは書きません。

## R. Regression

`F-NEW-1 PATH-B NEGATIVE CONTROL: PASS`（保存実行結果とtest semanticsの監査）

保存regression-results.txtはtest Git hash b8ae2d4997feffb8c887e59b07617bad060e2ce4aec98ce1ad6a60c7bee89793を示し、patchedはinstalled path・3/3 idl.has_lock=True・NB write ok・exit0、negativeはunpatched source path・3/3 neutron.has_lock=Trueかつidl.has_lock=False・NB write failed・exit1を示します。Tracebackのunpatched pathと生のRuntimeErrorはF-NEW-1条件に一致。

全test codeを独立に読取。real Neutron from_worker/DBInconsistenciesPeriodics、real python-ovs、private NB serverを使い、lock request send→request ID記録間を20ms延ばす。OVN clientはMagicMock、MaintenanceWorker.lock_nameはtestが設定するのでpost_fork_initializeの実行自体は試験しない。固定コードでは接続前lock設定によりconnection threadとのraceが成立しない。serverをmockで置換するテストではありません。

今回新たにtestを実行していません。保存runtime出力の監査であり、独立runtime再現とは区別します。handover範囲の欠落はTのblocking finding。

## S. RPC safety

`PATH-B RPC WORKERS REQUEST MAINTENANCE LOCK: NO`

独立PCAP parserを作成し、Ethernet/IPv4/TCPを解釈、sequenceでclient/server stream再構成、JSON-RPCをdecode、passive ssログとport/PIDを照合。rpcの8session・lock message0。maintenance31sessionは各1request、params=[ovn_db_inconsistencies_periodics]、全locked:true。

source traceでもMaintenanceWorkerだけがlock_nameを得てRpcWorkerには設定されない。harnessのRpcWorker lock_name=None/has_lock=Falseという別証拠も一致。

実PCAPは127 SYN sessionを含むが、保存wire-all.tsvは106。追加21はrerun側でlock0のsessionであり、31maintenance/8RPCの数は一致。保存summaryがPCAP全期間を網羅しないことはLOW（PB-04）。SYN→lock差0.6709–0.9339msは同PCAP clockでありproduction workerのPIDに対応。これはTCP SYN基準でありアプリのconnect完了時刻とは区別します。

## T. Lock handover

**未検証（要求された全behaviorは証拠に含まれない）。PASSは発行しません。**

regression-resultsのpatched側はA owner/B contended/Neutron B.has_lock=False、A停止後B.has_lock=Trueを記録。candidate testのhandover sectionはこのbooleanの検査だけです。

B待機中にguarded taskを呼び副作用が抑止されること、B取得後にguarded NB writeが成功することを実行していません。最初のsingle-worker 3回のNB writeは別のAPI instanceであり、Bのhandover後writeの代わりにはなりません。新PATH-B証拠にそれを補う実行記録もありません。PB-01 / MEDIUM / Blocking YES。これはroot-fixが壊れたという認定ではなく、PASS standard §39(26)の証拠不足です。

## U. Real acceptance

**包括PASSは未認定。**

保存node query記録ではmaintenance/periodic enabled/active、NRestarts0、API200/agents alive、boot19/17秒、両guest metadata instance-id成功、ping30/30、Geneve内request/reply30/30を支持します。検証scriptは意図した実API・guest・tcpdumpを使っています。

一方、保存collect.shはmaintenance log head25行、periodic head8行、journal head8行とgrep countを取るだけ。完全なproduction Neutron logやGeneve原captureは新証拠にありません。したがってwhole accepted processのNOT_LOCKED/ERROR/Tracebackと全trial guarded task完了を元ログから再検証できません。実装のsummaryのみで包括PASSにしていません。PB-02。

## V. Start trials

独立支持結果: **31/31 captured maintenance startsで各1lock request・取得成功**。さらにreboot-start1件のboot ID・PID・log excerptがあり、起動数は32を支持します。しかし **32/32 HEALTHYは認定しません**。

trials-Rは1..20、trials-Sは1..10で欠番/重複なし、child PIDは30個すべて独立解析したPCAPの1lock/locked:true sessionと一致。install child22592も同じで計31。TSVは各active/NRestarts0/notlocked0/tasks_finished23/failed0/guarded3を記録。

rebootはboot ID変更、13:20:41.658 startup、13:21:07.012 postinit、tree1338/2752を支持。reboot.txtの空countはreboot-final.txtで集計値に補完されています。ただしrebootの23/3 tasksと30trialの作業完了・error-free条件は集計値しかなく、production logの全trial intervalが未保存。PCAPはlock ownershipを示すが、指定された各guarded taskの完了を証明しません。PB-02 / MEDIUM / Blocking YES。

32回を確率0の証明とは扱いません。

## W. External nudge

新証拠のharnessはprivate NBを作成するovsdb-client transactを使用しますが、deploymentのovsdb-client lock/waiter/nudgeを実行する命令は確認していません。trial scriptはsystemctl restart/stopstartだけ、PCAPもpassive、独立解析ではmaintenance以外lock message0です。

ただし全remote command transcriptが保存されていないため「全行為の不使用」を無条件で認定しません。**保存されたproduction capture区間内でexternal lock requestは0**。rebootを含む全accepted trialsについての要求文言は未認定です。

## X. Runtime caveats

- INITIAL CAPTURE UNIT FAILURE: 仕組み上Neutron stateを変える操作ではない。ledger12:35:05Z、初Neutron startup12:40:10Zを支持。ただし失敗unitのjournal全文・packages still installingの対応timestampは未保存。NON-BLOCKINGと考えられるがtimelineの独立完全認定は未完了。
- RABBITMQ BOOT RETRIES: final snapshotはERROR6/Traceback0、RPC/periodic active、API200/agent aliveで回復を支持。ただし報告の13:20:46–48・impl_rabbitの6行自体は保存されていません。通常boot順序の説明を確定しません（PB-02のログ不足）。
- WPA-G1 SHUTOFF STATE: 先にcontroller guest ACTIVE・metadata・30/30 pingを完了した記録あり、F-NEW-1のboot/network試験をSHUTOFFだけで無効にはしない。ただしintentional later stateの命令やpost-reboot guest state query原文は未保存。SHUTOFF原因は未解明のままと記載し、製品欠陥とは認定しません。

## Y. Idempotency

`PATH-B RERUN IDEMPOTENCY: PASS`（保存before/after差分の範囲）

独立diffは先頭UTC timestampだけ。11unitのMainPID/ActiveEnterTimestamp、6 packageのNEVRA/header/INSTALLTIME、DNF transaction count6、4config hashは不変。aio-run2.rc=0、final API200/agent aliveを確認。不要reinstall/restartを示す変化なし。

## Z. Deferred items

`F13b: DEFERRED`

`CLIFF: DEFERRED`

`O-A: DEFERRED`

`TAG_REQUEST FINDING: DEFERRED`

`UBUNTU F-NEW-1: UNFIXED / HOLD`

cliffはnode queryでpython3-cliff-0:4.13.3-1.el10_2.noarch、from_repo=epel、SHA256HEADER ee157a61368e8cb1a86a7b49f711d8e10eb2a11ee3b4343816f31a5854d3fae3、PAYLOADDIGEST f2b8bd93ad79bc911fa391177eb8ff0fd4bc5d5e876657fdc0f654495ee14fa8。候補にcliff変更なし。lock pathはNeutron/ovs/ovsdbappを通りcliffを使わない。`CLIFF INTERVENTION: NON-BLOCKING / DEFERRED`。自己build cliff欠陥の独立再現は今回未実施。

## AA. Security

停止前に体系的な全preserved material secret scanは完了していません。読んだ候補patch・shim・test・query記録に実credentialを認識していませんが、`PATH-B TRACKED/PRESERVED SECRET MATERIAL: NONE` は未認定。公開source hash・projectを含むbuildhostはprivate key/tokenとは扱いません。この報告には実credentialを転載していません。

## AB. Cloud cleanup

`PATH-B CLOUD CLEANUP: COMPLETE`（保存baseline/final/delete記録の範囲）

baseline/finalはhgprov instance/disks0、既存disks集合同じ、snapshot94/hash同じ、firewall/address名同じ。delete.logはbuilder/rocky1/rocky2削除を示す。ledgerは対象3資源だけの作成・削除を記録。mikagami-validation/sinter-rc111-hv1は外部変化として記載され、remediationの操作対象という証拠はありません。全cloud audit logではないため、未記録の行為の絶対的不存在を証明するものではありません。

今回の監査でクラウド操作・VM作成は0。現在状態を再照会していません。監査専用外部SSD資料は人手reviewのため保存、元rawは変更・削除していません。

## AC. Findings

### PB-01 — MEDIUM — handover後のguarded workが未試験

- Evidence: candidate tests-neutron-maintenance-lock.pyのhandover section、PATH-B regression-results.txt。
- Description: ownership booleanだけでB待機中/取得後のguarded task・NB writeを実行していない。
- Impact: §25/§39(26)のruntime behaviorを証拠で閉じられない。
- Blocking: YES。
- 必要な補足: 同じB instanceで待機中guarded work抑止と、A停止→B取得後guarded NB write成功を示す生の実行記録。候補を変更せず、独立audit harnessによる新証拠であることを明示する必要がある。

### PB-02 — MEDIUM — critical runtime raw logs不足

- Evidence: collect.shのhead/count収集、raw/hgprov-rocky1の保存全file列挙、trials-R/S.tsv、reboot-final.txt、rocky1-final.txt。
- Description: production maintenance/periodic/RPCの完全ログがなく、trialのguarded task完了とERROR/NOT_LOCKED/Traceback全区間、RabbitMQ6行を元記録から独立復元できない。
- Impact: 32/32 HEALTHYと包括real runtime acceptanceを認定できない。31 lock acquisitionはPCAPで別途成立するが、その代替にならない。
- Blocking: YES。
- Stop: §43 critical PATH-B raw evidence missing、およびremaining evidence insufficient for acceptance。証拠gapをFAILにしていません。
- 必要な補足: 当該PATH-B nodeの完全production logs・trial/PID/time対応記録。存在しない歴史的証拠を新しい試験で補うなら、別campaignと明示し、旧32回のretroactive証明に使わないこと。

### PB-03 — LOW — SRPM→binary表の行見出し

- Evidence: remediation §S。
- Description: 実グラフはsibling outputs、表見出しはSRPM→binary。本文disclaimerは正しい。
- Impact: reviewerが強すぎる因果関係を読む可能性。
- Blocking: NO。実graphは独立成立。

### PB-04 — LOW — wire-allはPCAP全期間ではない

- Evidence: independent wire parser127 session、保存TSV106、追加21 sessionのlock0。
- Impact: summaryのtotal106をfull capture全体として読むと不正確。critical maintenance31/RPC8/lock countsは一致。
- Blocking: NO。

### PB-05 — NOTE — pre-existing python333/F13b-family

- Evidence: N。
- Impact: destroy-patch-ports.serviceのinvalid interpreter。candidate以前のspec副作用でmaintenance lock pathに不関与。
- Blocking: NO（今回のF-NEW-1範囲）。修復していません。

旧IA-R01はNEW setのbuild provenanceに限り閉鎖。旧artifactsは未確立のまま。

## AD. Audit mutation summary

`INDEPENDENT RECHECK PRODUCT MUTATIONS: ZERO`

- product/evidence Git objects不変
- remediation report SHA-256は開始baselineと終了で一致
- tracked modifications0、staged0、commits0、push0、PR0、tags/releases0
- 新規reportだけuntracked/unstaged、既存報告書上書き0
- 外部SSDに独立distgit bare clone、抽出SRPM/RPM、source comparison trees、独立header/PCAP parser・結果を保存
- 公式Neutron fetchは前回監査専用bare cloneのみ。product Gitを変更していません。
- cloud mutations0、heavy local virtualization0

有用な監査資料は /Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-pathb-independent-audit-2026-09-30/ に保持。実装raw evidenceは読み取りのみ。

## AE. Final verdict

ROCKY F-NEW-1 ROOT FIX: INDEPENDENT AUDIT INCONCLUSIVE
UBUNTU WP-A STATUS: HOLD
WP-A MERGE: HOLD
HAGISTACK ROCKY F-NEW-1 PATH-B RECHECK: INCONCLUSIVE

