# Rocky F-NEW-1 Final Focused Independent Recheck — 2026-10-01

判定: **INDEPENDENT AUDIT PASS / CLOSED**（Rocky F-NEW-1の指定candidateと既存PATH-B artifact setに限定）。前回のPB-01/PB-02は、新しいH1–H3および32-start campaignの一次証拠から独立に解消しました。Ubuntu WP-A/mergeはHOLDを継続します。

監査scopeは指定されたruntime証拠に限定。実装のPASS行・trials.tsv・TIMELINE・result/checker出力を根拠にせず、独立TCP/JSON-RPC decoderとproduction log/journal/DB observationsを使用。以前のcampaignを再解釈して新しい32回へ数え直していません。

Evidence root: `/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-runtime-evidence-remediation-2026-09-30/`。

表の時刻はprimary evidenceと合わせて**2026-09-30 UTC**。日本時間では2026-09-30夜〜2026-10-01未明に相当します。report dateは日本時間2026-10-01。

## A. Preflight

`PRODUCT CANDIDATE 40472e8: UNCHANGED`

`PREVIOUS VERIFIED BASELINE: UNCHANGED`

`UBUNTU PRODUCT CHANGES: ZERO`

- branch: `fix/rocky-neutron-maintenance-lock`
- HEAD: `207795084855e0fa7e3bce7124d4f0440408cfd4`
- origin/master（ローカルremote-tracking ref）: `7a20dbe1ba8cde14f9e35252e1f9074387d695d6`
- ahead/behind: 4/0
- tracked working/staged changes: 0
- 開始時untracked: AGENTS.mdと既存の調査・feasibility・監査・remediation報告7件、計8件。

```text
Product 40472e879bf55d66fb4f3ecb719d67fb180567d6
Parent  2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f
Tree    dbb2b2f1ad1dc41650a278467f20653d422966bf
Evidence 207795084855e0fa7e3bce7124d4f0440408cfd4
Parent   40472e879bf55d66fb4f3ecb719d67fb180567d6
Tree     9f5c17357de6464b0e957bec5b35189e28f91262
```

前回FINAL監査を読み、その独立成立項目（PATH-B sibling build provenance、candidate/spec関係、上流pair、4file bytes、RPC8sessions/lock0）を確認。旧監査の未成立項目をPASSとして継承していません。前回独立測定したSRPM＋binary15件のfull SHA-256、保存build transcript/log/shim/pre/post-bs inputs、repo bundle、RPC pcapsを再hashし不変を確認。前回4file comparisonの候補側source hashも不変。runtime preflightに記録された既存acceptance報告8件のhashは現在のファイルと一致。

代表identity:

- SRPM: `47f8cd8e7421b064fdf4ca4f15e5854917a92e01103a38cffd1bd5998f4a012c`
- python3-neutron binary: `1afd65940e98a29c2fb7c74b6daaa2a54185c9a80a1de7362e63c04228a94307`
- maintenance-worker binary: `e0012bdd042228118289e2426577bac456d99efa0b7cd37af894c2553140e4ac`
- repo bundle: `54cdb9bcf1fc2057d4bfb5036ca8bf5cc27db08125ea09c2f21e83cdc325c13e`

`git diff 40472e8 -- . ':!acceptance'`は空。Ubuntu/shared基盤は不変。前回の広範なbuild/source監査を再実行していません。

## B. Evidence integrity

`RUNTIME EVIDENCE MANIFEST: VERIFIED`

- SHA256SUMS SHA-256: `5bb0c112824543c185f3bd1eef89dafbb8d5c3800f66f3abfc39c5e9b22a09fb`
- 記載ファイル数: **1322**、独立再計算一致1322、欠落0、mismatch0。
- evidence treeのregular files: **1359**。
- root manifestに未記載: root SHA256SUMS、MANIFEST-INFO.txt、trial32＋handover3のlocal SHA256SUMS、計37件。新しいprimary evidenceの無記載はありません。
- local manifest35件は別途検証し、記載1266entryすべて一致。
- MANIFEST-INFO.txt SHA-256: `f4d4cc8de33432ca3aff64d2849bee84d1e463b6205d81baa47cd636d4d52fb3`。

サマリーtrials.tsv/TIMELINE/result/checker outputを判定根拠には使わず、raw PCAP・ss・journal・production log・DB observationから独立再構成。root/per-folder manifestsを監査後にも再検証し、変更していません。

## C. Handover code path

`HANDOVER GUARDED WORK USES REAL PRODUCTION PATH: YES`

前回byte-equivalenceを確認した候補source（今回hash不変）を直接読みました。maintenance.pyではguardが外側にあり、`has_lock_periodic`→`if not self.has_lock: return`（72–82行）→`log_maintenance_task`→body。`has_lock`は`not self._idl.is_lock_contended`（295–296行）。DEBUGのStarting body markerはguard通過後のみ出ます。

- `check_fdb_aging_settings`（799–840行）: NB_Global fdb_removal_limitを設定、check_error=Trueのtransaction。
- `set_fip_distributed_flag`（1145–1166行）: NB_Global external_ids neutron:fip-distributedをdb_set/execute(check_error=True)。
- `update_ha_failover`（1195–1228行）: bfd-mult等をset_nb_global_options/execute(check_error=True)。

`log_maintenance_task`（87–125行）は正常終了/NeverAgainだけでINFO finishedを記録し、例外はfailedを記録して再raise。bodyを呼ばずguardからreturnした場合はfinishedが出ません。

H1/H2/H3のpids.txtとjournalはA/Bの実process commandを示す。Bは実`/usr/bin/neutron-ovn-maintenance-worker`、User=neutron、Aと同じconfig arguments。差はBのlog pathと--debugのみ。harnessはclass/guard/bodyをmonkey-patchせず、synthetic lock clientでもありません。NB helperはplain select/updateでsentinelを書き、lock/steal/unlock/assertを送信しません。

観測対象はoptions bfd-mult=17/fdb_removal_limit=77、external_ids neutron:fip-distributed=hg-sentinel。候補の実bodyが3/0/Falseに戻すことをsource・wire update・DB samplesで三方向から確認。

## D. H1

`H1 WORKER IDENTITY: VERIFIED`

`H1 B CONTENDED: VERIFIED`

`H1 T0-T10: COMPLETE`

A PID 34725 / port 41220、B PID 36069 / port 54942。identityはpids.txt、A/pid.after、B/pid、B/command.txt、journal.raw、ss/ss.logのsession時間内サンプル（A lines [6633, 6636] / B lines [7208, 7212]）を照合。以下のevidence pathsは `handover/H1/` 相対。wireは `wire/lo6641-20260930T145419Z.pcap`、JSON-RPC IDとclient portで特定します。

| 遷移 | UTC時刻 | primary evidence / event |
|---|---|---|
| T0 A起動 | 15:07:31.804Z | events.tsv:2、A/command.txt、journal unit start |
| T1 A所有 | 15:07:35.256Z | PCAP port 41220、lock reply ID 2、locked:true |
| T2 B起動 | 15:08:16.413Z | events.tsv:6、B/command.txt、pids.txt |
| T3 B競合 | 15:08:19.292Z | PCAP port 54942、lock reply ID 2、locked:false |
| T4 作業due | 15:08:39.388Z〜15:10:19.414Z | 下表のfuturist callback records |
| T5 body抑止 | 同競合期間 | B full log body0/finished0、B assert0、NB samples全sentinel維持 |
| T6 A終了 | stop command 15:10:19.943Z / FIN 15:10:19.968Z | events.tsv:10、A/stop-state.txt、PCAP A client FIN |
| T7 B所有通知 | 15:10:19.969Z | 同じport 54942のserver `locked` notification |
| T8 body実行可 | 15:10:24.455Z | B full log Starting markers（下表） |
| T9 B作業完了 | 15:10:24.603Z | 同B PIDの3つのINFO finished（下表） |
| T10 効果確認 | 15:10:24.820Z | nb-samples.jsonlで全3値3/0/False、B asserted transaction replies |

| Operation | due回数（競合中） | body / finished（競合中） | due first / last line | body start（取得後） | finished（取得後） |
|---|---:|---|---|---|---|
| update_ha_failover | 21 | 0 / 0 | 1582 / 1971 | 15:10:24.601Z, line 2058 | 15:10:24.603Z, line 2062 |
| set_fip_distributed_flag | 21 | 0 / 0 | 1579 / 1968 | 15:10:24.590Z, line 2044 | 15:10:24.593Z, line 2048 |
| check_fdb_aging_settings | 21 | 0 / 0 | 1568 / 1960 | 15:10:24.455Z, line 2007 | 15:10:24.476Z, line 2011 |

上表line番号はlogs/ovn-maintenance-worker-B.log.full。競合中に毎5秒callbackがsubmitされ、body markers・finishedはゼロ。AにもB開始以後のguarded finished/assertはなく、Aの処理でsentinelが戻った可能性を除外。A stop-stateはResult=success / ExecMainStatus=0 / inactive。Bは同PID・同TCP sessionを維持し、別connectへの差し替えはありません。

sentinel samplingはNB helperのplain select。window-openからlocked notificationまで **94/94** が17/77/hg-sentinelを維持（15:08:39.809Z〜15:10:18.875Z）。A単独control6samplesも維持。全3値復元のfirst sampleは上表T10。

B sessionのassert transactionは競合中0、取得後 **3/3 accepted**。各requestのassert lock名・NB_Global update・対応idのreply `error:null`かつ各operation errorなし・count=1を確認。fdb→fip→HAのwrite内容とbody完了時刻が対応し、DBの3値復元も一致。

client FIN→B locked notificationの独立計測は **0.288ms**。同PCAP clockによる観測差でありCPU内部状態のtransition時間ではありません。報告のmillisecond表示からの約1msとの差は丸め/closure marker定義の範囲として記載します。

`H1 LOCK HANDOVER: VERIFIED`

`H1 B GUARDED WORK AFTER HANDOVER: VERIFIED`

`H1 ASSERTED TRANSACTIONS ACCEPTED: 3/3`

`H1 SENTINELS RESTORED: YES`

`H1 GUARDED TASK OPPORTUNITIES WHILE CONTENDED: 21/21/21`

`H1 GUARDED TASK BODY EXECUTIONS WHILE CONTENDED: 0/0/0`

`H1 CONTENDED SENTINELS UNCHANGED: 94/94`


## E. H2

`H2 WORKER IDENTITY: VERIFIED`

`H2 B CONTENDED: VERIFIED`

`H2 T0-T10: COMPLETE`

A PID 43813 / port 57614、B PID 45131 / port 56868。identityはpids.txt、A/pid.after、B/pid、B/command.txt、journal.raw、ss/ss.logのsession時間内サンプル（A lines [10855, 10858] / B lines [11429, 11433]）を照合。以下のevidence pathsは `handover/H2/` 相対。wireは `wire/lo6641-20260930T145419Z.pcap`、JSON-RPC IDとclient portで特定します。

| 遷移 | UTC時刻 | primary evidence / event |
|---|---|---|
| T0 A起動 | 15:12:17.538Z | events.tsv:2、A/command.txt、journal unit start |
| T1 A所有 | 15:12:20.948Z | PCAP port 57614、lock reply ID 2、locked:true |
| T2 B起動 | 15:13:01.975Z | events.tsv:6、B/command.txt、pids.txt |
| T3 B競合 | 15:13:04.890Z | PCAP port 56868、lock reply ID 2、locked:false |
| T4 作業due | 15:13:24.987Z〜15:15:05.013Z | 下表のfuturist callback records |
| T5 body抑止 | 同競合期間 | B full log body0/finished0、B assert0、NB samples全sentinel維持 |
| T6 A終了 | stop command 15:15:05.489Z / FIN 15:15:05.514Z | events.tsv:10、A/stop-state.txt、PCAP A client FIN |
| T7 B所有通知 | 15:15:05.515Z | 同じport 56868のserver `locked` notification |
| T8 body実行可 | 15:15:10.054Z | B full log Starting markers（下表） |
| T9 B作業完了 | 15:15:10.208Z | 同B PIDの3つのINFO finished（下表） |
| T10 効果確認 | 15:15:10.402Z | nb-samples.jsonlで全3値3/0/False、B asserted transaction replies |

| Operation | due回数（競合中） | body / finished（競合中） | due first / last line | body start（取得後） | finished（取得後） |
|---|---:|---|---|---|---|
| update_ha_failover | 21 | 0 / 0 | 3670 / 4056 | 15:15:10.205Z, line 4143 | 15:15:10.208Z, line 4147 |
| set_fip_distributed_flag | 21 | 0 / 0 | 3666 / 4053 | 15:15:10.194Z, line 4129 | 15:15:10.197Z, line 4133 |
| check_fdb_aging_settings | 21 | 0 / 0 | 3653 / 4045 | 15:15:10.054Z, line 4092 | 15:15:10.077Z, line 4096 |

上表line番号はlogs/ovn-maintenance-worker-B.log.full。競合中に毎5秒callbackがsubmitされ、body markers・finishedはゼロ。AにもB開始以後のguarded finished/assertはなく、Aの処理でsentinelが戻った可能性を除外。A stop-stateはResult=success / ExecMainStatus=0 / inactive。Bは同PID・同TCP sessionを維持し、別connectへの差し替えはありません。

sentinel samplingはNB helperのplain select。window-openからlocked notificationまで **94/94** が17/77/hg-sentinelを維持（15:13:25.348Z〜15:15:04.424Z）。A単独control6samplesも維持。全3値復元のfirst sampleは上表T10。

B sessionのassert transactionは競合中0、取得後 **3/3 accepted**。各requestのassert lock名・NB_Global update・対応idのreply `error:null`かつ各operation errorなし・count=1を確認。fdb→fip→HAのwrite内容とbody完了時刻が対応し、DBの3値復元も一致。

client FIN→B locked notificationの独立計測は **0.451ms**。同PCAP clockによる観測差でありCPU内部状態のtransition時間ではありません。報告のmillisecond表示からの約1msとの差は丸め/closure marker定義の範囲として記載します。

`H2 LOCK HANDOVER: VERIFIED`

`H2 B GUARDED WORK AFTER HANDOVER: VERIFIED`

`H2 ASSERTED TRANSACTIONS ACCEPTED: 3/3`

`H2 SENTINELS RESTORED: YES`


## F. H3

`H3 WORKER IDENTITY: VERIFIED`

`H3 B CONTENDED: VERIFIED`

`H3 T0-T10: COMPLETE`

A PID 50906 / port 51008、B PID 52317 / port 53424。identityはpids.txt、A/pid.after、B/pid、B/command.txt、journal.raw、ss/ss.logのsession時間内サンプル（A lines [14063, 14066] / B lines [14642, 14646]）を照合。以下のevidence pathsは `handover/H3/` 相対。wireは `wire/lo6641-20260930T145419Z.pcap`、JSON-RPC IDとclient portで特定します。

| 遷移 | UTC時刻 | primary evidence / event |
|---|---|---|
| T0 A起動 | 15:15:45.217Z | events.tsv:2、A/command.txt、journal unit start |
| T1 A所有 | 15:15:48.671Z | PCAP port 51008、lock reply ID 2、locked:true |
| T2 B起動 | 15:16:29.737Z | events.tsv:6、B/command.txt、pids.txt |
| T3 B競合 | 15:16:32.591Z | PCAP port 53424、lock reply ID 2、locked:false |
| T4 作業due | 15:16:52.685Z〜15:18:27.713Z | 下表のfuturist callback records |
| T5 body抑止 | 同競合期間 | B full log body0/finished0、B assert0、NB samples全sentinel維持 |
| T6 A終了 | stop command 15:18:32.122Z / FIN 15:18:32.149Z | events.tsv:10、A/stop-state.txt、PCAP A client FIN |
| T7 B所有通知 | 15:18:32.149Z | 同じport 53424のserver `locked` notification |
| T8 body実行可 | 15:18:32.755Z | B full log Starting markers（下表） |
| T9 B作業完了 | 15:18:32.927Z | 同B PIDの3つのINFO finished（下表） |
| T10 効果確認 | 15:18:33.442Z | nb-samples.jsonlで全3値3/0/False、B asserted transaction replies |

| Operation | due回数（競合中） | body / finished（競合中） | due first / last line | body start（取得後） | finished（取得後） |
|---|---:|---|---|---|---|
| update_ha_failover | 20 | 0 / 0 | 5752 / 6122 | 15:18:32.924Z, line 6209 | 15:18:32.927Z, line 6213 |
| set_fip_distributed_flag | 20 | 0 / 0 | 5749 / 6119 | 15:18:32.914Z, line 6195 | 15:18:32.916Z, line 6199 |
| check_fdb_aging_settings | 20 | 0 / 0 | 5737 / 6111 | 15:18:32.755Z, line 6158 | 15:18:32.780Z, line 6162 |

上表line番号はlogs/ovn-maintenance-worker-B.log.full。競合中に毎5秒callbackがsubmitされ、body markers・finishedはゼロ。AにもB開始以後のguarded finished/assertはなく、Aの処理でsentinelが戻った可能性を除外。A stop-stateはResult=success / ExecMainStatus=0 / inactive。Bは同PID・同TCP sessionを維持し、別connectへの差し替えはありません。

sentinel samplingはNB helperのplain select。window-openからlocked notificationまで **93/93** が17/77/hg-sentinelを維持（15:16:53.012Z〜15:18:31.055Z）。A単独control6samplesも維持。全3値復元のfirst sampleは上表T10。

B sessionのassert transactionは競合中0、取得後 **3/3 accepted**。各requestのassert lock名・NB_Global update・対応idのreply `error:null`かつ各operation errorなし・count=1を確認。fdb→fip→HAのwrite内容とbody完了時刻が対応し、DBの3値復元も一致。

client FIN→B locked notificationの独立計測は **0.292ms**。同PCAP clockによる観測差でありCPU内部状態のtransition時間ではありません。報告のmillisecond表示からの約1msとの差は丸め/closure marker定義の範囲として記載します。

`H3 LOCK HANDOVER: VERIFIED`

`H3 B GUARDED WORK AFTER HANDOVER: VERIFIED`

`H3 ASSERTED TRANSACTIONS ACCEPTED: 3/3`

`H3 SENTINELS RESTORED: YES`


## G. Handover verdict

`MAINTENANCE LOCK HANDOVER WITH GUARDED WORK: 3/3 PASS`

前回PB-01は新H1–H3の実production-path試験で閉鎖。旧harnessのboolean-only結果をretroactively強化したものではありません。競合中のBへassert writeを強制してserver rejectionを観測する追加試験は要求せず、real contention・repeated opportunities・body抑止・sentinel維持・same-session取得後成功でclient guardを検証しました。

## H. Trial dataset

`NEW TRIAL SET: 32`

trial directoryを独立列挙し001..032の連番、重複/欠番なし。command.txtとjournalによる分類はinstall1、systemctl restart20（002..021）、stop/start10（022..031）、reboot1（032）。以前の32/42起動は含めません。handover A/B/cleanup起動9件も別扱い。trial002の旧PID56962はH3 cleanup起動、trial003以後のpid.beforeは直前trialのpid.afterに一致。

## I. Trial attribution

`32/32 TRIAL BOUNDARIES: VERIFIED`

`32/32 WORKER PID TO LOCK SESSION: VERIFIED`

各trialの保存command/t_before/action/complete/end、journal cursorとunit-start record、psのmaintenance-child PID、時刻範囲内ss port/PID、raw PCAP lock/transactionを独立照合。PID32件はすべて異なりpid.beforeとも異なる。隣接trialの期間は非重複。各journalにproduction maintenance unitのStarted recordが1つ、同trial内に新規lock sessionは当該workerの1つだけ。全log segmentは保存inode/byte offsetからfinal production logの対応bytesと一致（すべてのNeutron logについて確認）。古いlog行を別trialに流用していません。

trial1はinstaller完了前にguarded workを実行するのでcommand終了とwork完了の順序を同一と仮定せず、action開始からtrial終了の範囲で確認。trial32はrebootによりcommand.rc/action-endが構造的に空ですが、boot-ID変更・monotonic reset・boot journal・同PID/session/workを確認してboundaryを確立。

## J. Lock capture

`CAPTURED MAINTENANCE LOCK REQUESTS: 41`

`NON-MAINTENANCE LOCK REQUESTS: 0`

`DUPLICATE LOCK REQUESTS PER WORKER: 0`

rootの2PCAPを独立parserでEthernet→IPv4→TCP sequence stream→JSON-RPCに復元。ポート再利用/別bootを別sessionとして扱い、retransmission重複は除外。672sessions、41 lock requests、steal/unlock0。全41に時間内ss PID対応あり、processはmaintenance worker。38初回locked:true、H1/H2/H3のB3件はlocked:false後に同sessionでlocked notification。受入に使うsessionはTCP gap0・JSON framing incomplete0。

41=trial32＋handover(A/B)6＋handover cleanup3。非maintenanceのrpc/httpd/nbqにはlock methodなし。count aloneではなくsessionごとの実messageを使用。

## K. Guarded work

`GUARDED WORK COMPLETION EVIDENCE: 32/32`

`NEW PATH-B START TRIALS: 32/32 HEALTHY`

以下のlogsは各runtime-evidence/trial-NNN/logs/ovn-maintenance-worker.log.raw、journal番号は同directoryのjournal.raw。PCAPはportと同時刻範囲で指定。3つのfinished markers（HA/FIP/FDB）を直接読み、request/replyとNB effectを照合。NLはbounded maintenance-logのNOT_LOCKED/require-lock count。

| Trial | Type | PID | Lock/session / journal Started line | Guarded completion（HA / FIP / FDB: UTC, log line） | NL | Result |
|---|---|---:|---|---|---:|---|
| 001 | install | 21826 | port 47696, lock1/true, asserts 4/4; J1080 | 15:00:44.145Z L213 / 15:00:44.135Z L210 / 15:00:44.076Z L198 | 0 | PASS |
| 002 | restart | 59276 | port 56974, lock1/true, asserts 3/3; J10 | 15:20:19.590Z L214 / 15:20:19.580Z L211 / 15:20:19.389Z L199 | 0 | PASS |
| 003 | restart | 60580 | port 41678, lock1/true, asserts 3/3; J7 | 15:20:57.498Z L214 / 15:20:57.489Z L211 / 15:20:57.289Z L199 | 0 | PASS |
| 004 | restart | 61872 | port 33060, lock1/true, asserts 3/3; J7 | 15:21:35.344Z L214 / 15:21:35.335Z L211 / 15:21:35.144Z L199 | 0 | PASS |
| 005 | restart | 63243 | port 50272, lock1/true, asserts 3/3; J38 | 15:22:13.240Z L214 / 15:22:13.230Z L211 / 15:22:13.032Z L199 | 0 | PASS |
| 006 | restart | 64591 | port 45470, lock1/true, asserts 3/3; J30 | 15:22:51.077Z L214 / 15:22:51.068Z L211 / 15:22:50.867Z L199 | 0 | PASS |
| 007 | restart | 65974 | port 35822, lock1/true, asserts 3/3; J30 | 15:23:28.981Z L214 / 15:23:28.972Z L211 / 15:23:28.793Z L199 | 0 | PASS |
| 008 | restart | 67355 | port 33292, lock1/true, asserts 3/3; J38 | 15:24:06.847Z L214 / 15:24:06.838Z L211 / 15:24:06.646Z L199 | 0 | PASS |
| 009 | restart | 68748 | port 54252, lock1/true, asserts 3/3; J38 | 15:24:44.757Z L214 / 15:24:44.747Z L211 / 15:24:44.540Z L199 | 0 | PASS |
| 010 | restart | 70092 | port 57764, lock1/true, asserts 3/3; J7 | 15:25:22.646Z L214 / 15:25:22.637Z L211 / 15:25:22.434Z L199 | 0 | PASS |
| 011 | restart | 71482 | port 40788, lock1/true, asserts 3/3; J30 | 15:26:00.563Z L214 / 15:26:00.555Z L211 / 15:26:00.369Z L199 | 0 | PASS |
| 012 | restart | 72861 | port 56516, lock1/true, asserts 3/3; J30 | 15:26:38.436Z L214 / 15:26:38.426Z L211 / 15:26:38.221Z L199 | 0 | PASS |
| 013 | restart | 74243 | port 34040, lock1/true, asserts 3/3; J38 | 15:27:16.331Z L214 / 15:27:16.320Z L211 / 15:27:16.098Z L199 | 0 | PASS |
| 014 | restart | 75595 | port 51620, lock1/true, asserts 3/3; J7 | 15:27:54.212Z L214 / 15:27:54.202Z L211 / 15:27:54.007Z L199 | 0 | PASS |
| 015 | restart | 76979 | port 34878, lock1/true, asserts 3/3; J30 | 15:28:32.114Z L214 / 15:28:32.105Z L211 / 15:28:31.906Z L199 | 0 | PASS |
| 016 | restart | 78358 | port 47826, lock1/true, asserts 3/3; J38 | 15:29:09.996Z L214 / 15:29:09.987Z L211 / 15:29:09.794Z L199 | 0 | PASS |
| 017 | restart | 79751 | port 54788, lock1/true, asserts 3/3; J38 | 15:29:47.998Z L214 / 15:29:47.989Z L211 / 15:29:47.790Z L199 | 0 | PASS |
| 018 | restart | 81104 | port 44888, lock1/true, asserts 3/3; J34 | 15:30:25.948Z L214 / 15:30:25.939Z L211 / 15:30:25.725Z L199 | 0 | PASS |
| 019 | restart | 82487 | port 51124, lock1/true, asserts 3/3; J31 | 15:31:03.940Z L214 / 15:31:03.931Z L211 / 15:31:03.732Z L199 | 0 | PASS |
| 020 | restart | 83870 | port 44824, lock1/true, asserts 3/3; J38 | 15:31:41.925Z L214 / 15:31:41.914Z L211 / 15:31:41.712Z L199 | 0 | PASS |
| 021 | restart | 85263 | port 39044, lock1/true, asserts 3/3; J38 | 15:32:19.933Z L214 / 15:32:19.923Z L211 / 15:32:19.686Z L199 | 0 | PASS |
| 022 | stopstart | 86656 | port 60730, lock1/true, asserts 3/3; J7 | 15:32:59.788Z L214 / 15:32:59.779Z L211 / 15:32:59.587Z L199 | 0 | PASS |
| 023 | stopstart | 88088 | port 54836, lock1/true, asserts 3/3; J30 | 15:33:39.721Z L214 / 15:33:39.712Z L211 / 15:33:39.507Z L199 | 0 | PASS |
| 024 | stopstart | 89521 | port 50264, lock1/true, asserts 3/3; J30 | 15:34:19.617Z L214 / 15:34:19.608Z L211 / 15:34:19.403Z L199 | 0 | PASS |
| 025 | stopstart | 90956 | port 45200, lock1/true, asserts 3/3; J7 | 15:34:59.548Z L214 / 15:34:59.538Z L211 / 15:34:59.333Z L199 | 0 | PASS |
| 026 | stopstart | 92392 | port 33410, lock1/true, asserts 3/3; J38 | 15:35:39.617Z L214 / 15:35:39.607Z L211 / 15:35:39.411Z L199 | 0 | PASS |
| 027 | stopstart | 93829 | port 40232, lock1/true, asserts 3/3; J38 | 15:36:19.654Z L214 / 15:36:19.645Z L211 / 15:36:19.445Z L199 | 0 | PASS |
| 028 | stopstart | 95220 | port 41576, lock1/true, asserts 3/3; J7 | 15:36:59.645Z L214 / 15:36:59.636Z L211 / 15:36:59.428Z L199 | 0 | PASS |
| 029 | stopstart | 96655 | port 48246, lock1/true, asserts 3/3; J30 | 15:37:39.617Z L214 / 15:37:39.607Z L211 / 15:37:39.409Z L199 | 0 | PASS |
| 030 | stopstart | 98088 | port 54304, lock1/true, asserts 3/3; J30 | 15:38:19.576Z L214 / 15:38:19.567Z L211 / 15:38:19.365Z L199 | 0 | PASS |
| 031 | stopstart | 99524 | port 39446, lock1/true, asserts 3/3; J30 | 15:38:59.588Z L214 / 15:38:59.579Z L211 / 15:38:59.391Z L199 | 0 | PASS |
| 032 | reboot | 3009 | port 53210, lock1/true, asserts 4/4; J14740 | 15:41:57.193Z L216 / 15:41:57.179Z L213 / 15:41:56.931Z L199 | 0 | PASS |

trial001..031のsessionはlo6641-20260930T145419Z.pcap、trial032はlo6641-20260930T154123Z.pcap。31 sentinel-precondition付きtrialは直前17/77/hg-sentinel→work後3/0/False、全trialに3operation実完了。旧PB-02はこのNEW datasetについて閉鎖。


## L. F-NEW-1 signature

`F-NEW-1 SIGNATURE: 0/32`

全trialの**完全bounded primary maintenance log**をreadし、当該PIDの三operation finished、lock reply、assert acceptedと照合。NOT_LOCKED/require-lock/Traceback/ERROR-level/failed task0、NRestarts0。journalにもcompletion前の追加unit起動/automatic restart jobなし。false-owner conditionを「ERRORがない」だけで判定せず、real server ownership＋assert受理＋body完了＋effectを要求しました。

`REBOOT TRIAL: PASS`

boot-IDはa13d71b3…→31f4d494…、boot0 complete journal先頭monotonic1.590182s。new PID3009/port53210、lock1/true、assert4/4、guarded completion15:41:56.931〜15:41:57.193、effect restored。post-reboot API/agent/service sanityは正常で、lock-related interventionなし。

## M. Asserted transactions

`ASSERTED TRANSACTIONS: 109`

`ASSERTED TRANSACTION ERRORS: 0`

全wireのtransact中assert opを数え、同session/JSON-RPC idのreplyを関連付け。outer errorだけでなく各operationのerrorも確認。error:nullは成功として扱い、reply absentを成功にしません。109件すべてreplyあり・エラーなし。

内訳は32trialの98件（install/reboot4ずつ、残り30trial3ずつ）、handover B9件、H1 A2件。cleanupや他clientのassert0。これらは対応するtrial/handover window内に属します。重複パケット/responseを別transactionとして数えません。

## N. Checker audit

`CHECKER BUGS AFFECT PRIMARY EVIDENCE: NO`

`TWO-CHECKER RESULT: 32/32 CONSISTENT`

analyze_trials.py＋wire_decode.pyはsequence/JSON-RPC decoderとraw worker logを使う。reconstruct_independent.pyは共有importせずsystem tcpdump -Aと自身のregex・ss・NB JSONを使う。後者はtrials.tsvを**comparisonだけ**に使用し、healthy_nはprimary inputsから導出。二つが同じresult.txtをwrapするものではありません。保存outputは双方32/32と一致。本監査は両checkerを再実行せず、第三の独立parser/再構成で同じ結果を得ました。

ledgerは最初のerror:null誤検出による0/32とregex修正を記録。修正後regexはnullを除外するので当該bugに妥当。ただし第二checkerの文字列検索はTCP framing/message-idに関して第一より弱く、主証拠の代わりにはしません。本監査はnested operation errorまでJSONとして確認。

loose ERROR grepはBのDEBUG config dump中のlogging_exception_prefixを拾うため不適切。実level columnはDEBUGで、primary body/work/wireと矛盾しません。current checkerはlevel columnを見る。ledgerにこの第二bugの独立timestamp行はなく、remediation本文で説明されています（非阻害のtooling disclosure限界）。

primary immutabilityはroot/local manifest、trial logsのfinal originalとのbyte一致、原PCAPの直接decodeで確認。checkerの修正を原ログ改変として扱う証拠はありません。

## O. Caveats

`TRIAL 1 SENTINEL EXCEPTION: NON-BLOCKING`

install前のsnapshotはOpenStack packages0・NB接続不可。sentinel-beforeを持てないが、初worker21826のprimary finished3件、port47696 ownership、assert4/4、after-NB3/0/Falseが成立。

`PRE-COUNT SELINUX SETUP FAILURES: NON-BLOCKING`

full journal: 14:53:52.720Z ss sampler203/EXEC、wire unitもexit-code。capture/sampler復旧14:54:19Z。初trial launcherは14:54:32.460Z、exec Permission denied/203なのでbody実行前の失敗。/bin/bash launcherが14:54:47.825ZにStarted、accepted action開始14:54:47.999Z。最初のmaintenance lockは15:00台。失敗unitはproduction workerやNB lock clientではなく、trial1のprimary NB/worker起動前。追加lock request/hidden counted workerはwire/journalにありません。

`DISCLOSED UNRELATED LOG NOISE: NON-BLOCKING`

- RabbitMQ: final rpc-server.log lines413,421–425の6 ERROR。3PID3042/3045/3054、15:41:36.721〜15:41:37.774、logger impl_rabbit、Connection refused retry。maintenance PID3009のguarded workは15:41:56.931〜57.193に完了。後段RPC/agents/APIが回復、manual recoveryなし。
- Nova: reboot shutdown時MariaDB停止に伴うOperationalErrorをpreserved journalで確認。**独立count230 distinct entries**、15:39:31.969〜15:40:59.619。remediationの478と一致しません（UのRF-01）。maintenanceのpost-boot work/ownershipを無効にするものではありません。
- Startup WARNING: deprecated tenant_network_types/api_paste_config、Stdattrs_common、spawn→fork fallback、OVN/Neutron host mapping等。columnをWARNINGとして保持し、work complete/accepted transactionsと照合。ERRORに誤分類しません。shutdown時旧RPC connection warningsは別process。
- Bは--debug/別log fileで観測可視性を増したproduction worker。guardやbodyの置換なし。
- Contended sessionからserver-rejected writeを強制する試験は未実施。production client guard抑止と取得後write成功が監査対象なので阻害しません。

`RUNTIME EVIDENCE GENERALIZATION: BOUNDED`

one node / one build / one imageの実行証拠。32/32や3/3を他環境の失敗確率0の統計的証明とは解釈しません。旧network/idempotency campaignは再実行していません。

## P. Healing intervention

`EXTERNAL LOCK NUDGE USED: NO`

`ACCEPTED TRIALS REQUIRED HEALING INTERVENTION: NO`

harness lib/campaign/handover/nbq/reboot scripts、保存commands、journal、全lock trafficを確認。plain NB select/updateはownershipに触れずlock/assertを要求しない。全41lock requestは既知maintenance PIDに対応、steal/unlock0。手動ovsdb-client lock/waiter clientなし。各accepted action→guarded completion間のproduction unit起動は1回、main PID/childが対応しNRestarts増加0。handover cleanup再起動3件は観測完了後でtrial counts外。

sourceとwireは、成功が外部lock再通知/nudgeによってhealしたという説明を支持しません。shell historyは保存されていないため使わず、実unit/journal/wire/command boundariesで検証しました。

## Q. Artifact/product immutability

`RUNTIME REMEDIATION USED EXISTING PATH-B ARTIFACTS: YES`

`RUNTIME REMEDIATION PRODUCT MUTATIONS: ZERO`

frozen16RPM・repo/build/source baselineはAのhash検証で不変。runtime candidate archive SHA-256は2208303d5a2353adedaff788bc17fb9f681d0044e9b2767e10819a83f37cf3e9で候補archiveに一致。

finalの**raw rpm-qa-digests.tsv / dnf-from-repo.tsv**を独立joinし、frozen inventoryのNEVRA＋SHA256HEADER＋PAYLOADDIGESTを比較: 104/104、Neutron8件すべて一致。32trialのpackages.txtは各8件、H1–H3は各4件で35snapshotすべて既存binary identityと一致。hagistack full hash082a4a8c3879fedd1b0db262cea83fa39c63d7e4edba2536959f1e58c453e170も一致。

runtime scriptsにproduct source/test/spec/manifest/RPM再build・package code置換はない。候補Git/既存evidence commitは不変、既存報告hash8件も一致。追加unit/harnessはdisposable VM内だけ。

## R. Security

`RUNTIME EVIDENCE SECRET MATERIAL: NONE`

実装secret-scan.txtのCLEANだけに依存せず、1359regular filesをprivate-key headers、cloud access/token patterns、literal OS_PASSWORD/AWS secret assignment、非masked DB/rabbit credential URLsで独立scan。final DEBUG configの該当credential fieldsは****でmasked。PCAPはNB OVSDBに限定され、実token/key/passwordは発見されません。

candidate tarに出たURL候補4箇所はUbuntu旧reportのREDACTED marker1件、既存container test fixture3件で、live credentialsとして扱いません。公開hash/project-bearing buildhostは秘密と判定しません。raw値をこのreportへ転載していません。

これは実際に保存されたevidenceのreview結果であり、pattern scanだけで未知形式の秘密の数学的不存在を証明する主張ではありません。

## S. Cloud cleanup

`RUNTIME REMEDIATION CLOUD CLEANUP: COMPLETE`

`UNRELATED INSTANCES TOUCHED BY REMEDIATION: NO`（保存command/resource記録の範囲）

vm-create/delete、cloud baseline/final、ledgerを照合。作成対象はhgrt-rocky1のみ、delete記録あり。final hgrt-* instance/disk0、既存disk集合・snapshot94/md5・firewall6・address1がbaseline一致。extra snapshot/firewall/address作成命令なし。

mikagami-validation TERMINATED→RUNNING、sinter-rc111-hv1 RUNNING→TERMINATEDはquery結果として記録するだけ。保存remediationのmutation targetに両者はありません。外部変化をremediationへ帰属せず、戻す操作もしていません。全GCP監査ログを取得したという主張ではありません。

今回auditはクラウドへ照会/作成/開始/停止/削除を一切実施せず、保存cleanup evidenceのみを検証しました。

## T. Deferred items

`F13b: DEFERRED`

`CLIFF: DEFERRED`

`O-A: DEFERRED`

`TAG_REQUEST FINDING: DEFERRED`

`UBUNTU F-NEW-1: UNFIXED / HOLD`

c695003d optional has_lockは含めず、tag_request/O-A/F13b/cliff/Ubuntuを修正していません。既存cliff検証介入とartifact varianceに関する前回の限定は継続。このfocused PASSはWP-A全体のmerge許可ではありません。

## U. Findings

### RF-01 — LOW — Nova transient errorの集計差

- Evidence: runtime remediation §Pの478、trial032/journal.raw、final/journal-all-boots.json、previous-boot complete journal。
- Independent result: 各datasetでOperationalErrorを含む230entry、230unique cursors、duplicate0。MESSAGE内の行/出現数も230。478は保存一次証拠から再現しません。
- Impact: unrelated Nova shutdown noiseのcount表現が不正確。maintenance32trial/ownership/guarded work/F-NEW-1結果には影響なし。
- Blocking: NO。証拠を書き換えず実測値を記録。

### RF-02 — NOTE — handover timingの表示限界

- Evidence: client FINとserver locked notificationのraw PCAP。
- Independent result: H1 0.288ms、H2 0.451ms、H3 0.292ms（first client FIN基準）。報告のmillisecond文字列からの約1msは粗い表示。
- Impact: wire marker/丸めを明示する必要。handover correctnessには影響なし。
- Blocking: NO。

### 前回findingの扱い

- PB-01: **CLOSED**（新H1–H3で同Bのguarded work抑止/取得後成功を証明）。
- PB-02: **CLOSED**（新32trialの完全primary logs・wire・PID・effectsで再構成）。
- IA-R01: NEW PATH-B setに限って前回解消済み、baseline不変。旧original artifactsの歴史的来歴は未確立のまま。
- PB-03/PB-04: 前回のLOW表現/summary coverage observationsは変更せず、今回の判断はその誤った見出し/不完全summaryに依存しない。
- Pre-existing python333/F13b-family: DEFERRED、今回scopeで修復しない。

新blocking finding: **0**。上記LOW/NOTEを修正していません。

## V. Audit mutations

`FOCUSED INDEPENDENT RECHECK PRODUCT MUTATIONS: ZERO`

- tracked modifications0 / staged0 / commits0 / pushes0 / PR0 / tags/releases0
- candidate/evidence object identity不変
- 新規reportのみuntracked/unstaged。既存report上書きなし、既存8報告hashは不変。
- preserved runtime evidence・root/sub manifests・raw logs・scriptsを変更せず、最終integrity checkも一致。
- test rerun0 / RPM rebuild0 / evidence regeneration0 / product/checker fixes0
- cloud mutation0 / local VM-container0
- 外部SSD監査専用directoryだけにread-only parser、reconstruction JSON、report generatorを新規作成。元evidence treeの外側。

人手review用の監査資料は /Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-focused-independent-recheck-2026-10-01/ に保存。raw evidenceをcleanupで削除していません。

## W. Final verdict

ROCKY F-NEW-1 ROOT FIX: INDEPENDENT AUDIT PASS
ROCKY F-NEW-1 ROOT FIX: CLOSED
UBUNTU WP-A STATUS: HOLD
WP-A MERGE: HOLD
HAGISTACK ROCKY F-NEW-1 FINAL FOCUSED RECHECK: PASS

