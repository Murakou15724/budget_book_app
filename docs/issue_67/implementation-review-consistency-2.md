## 確認範囲
- GitHub Issue #67・親Issue #65本文、承認済み詳細設計コメント `6262287659`
- 基点 `833c3f43d36e4426edfb1568ff0e13971056fa2a` との差分、Git状態、未追跡の実装・spec
- 取込関連モデル・Service・Controller・View、Transaction callback、migration・schema
- 新規・既存関連spec、仕様書、移行・schema検証スクリプト
- MySQL／PostgreSQLのmigration構築・schema構築後の全件ログ：各250 examples、0 failures、8 pending。レビュー中のテスト実行なし

## トレーサビリティ

| 要求 | 設計節 | 実装箇所 | テスト |
|---|---|---|---|
| 出所・元口座・候補・反映先・結果の追跡 | §3・4・9 | `app/models/import_entry.rb:5`、`app/views/import_documents/_summary.html.erb:1` | import_history_spec、import_tracking_spec |
| 再送・二重承認・並行・途中失敗で二重反映しない | §6.1～6.3 | ImageReceiver、Applier | Receiver、Applier、Concurrency spec。Guard初期化との組合せに不足 |
| 同一外部IDの重複防止・訂正の保留 | §4・5.1・5.2 | EntryRecorder、Applier | entry_recorder_spec |
| 同額の正当な複数取引・類似の明示判断 | §5.1・5.2 | Matcher、Applier | applier_spec、receiver_concurrency_spec |
| 手入力・予定との一致候補・対応先の確認 | §5.2・9 | 候補詳細、Applier | import_entry_resolution_spec、applier_spec |
| 保留の自動反映停止、変更・削除の矛盾検出 | §5.3・6.3 | Applier、ImportTargetTracking | Applier spec。支払操作との結合検証に不足 |
| 件数・理由・元候補・処理後履歴 | §9・11 | ImageImportDraftsController、文書summary | import_history_spec。50文書超に欠落 |
| 複数口座・月跨ぎ・競合・失敗・訂正 | §8・10 | Matcher、migration | 各境界spec、並行spec、旧候補移行検証 |

## 指摘

### [MAJOR]-1 レビュー一覧が最新50文書以外の未処理候補を隠す
- 箇所: `app/controllers/image_import_drafts_controller.rb:3`・`:6`・`:14`、`app/views/image_import_drafts/index.html.erb:10`
- 根拠: 詳細設計§9は「今回のDocument集合のサマリ」、§11は「通常一覧は50件ずつ」を要求する。実装は処理済みも含む最新50文書に限定してから未処理候補を取得し、この画面にはページ送りがない。
- 問題: 古い未処理候補が残っていても、その後に50文書取り込むと「レビュー待ちの候補はありません」と表示される。今回のdocument_idsが51件以上の場合も、一部が説明なく落ちる。
- 修正方針: 通常の未処理一覧と明示された文書集合について、全対象へ到達できるページ送りを実装する。最新50文書が処理済みで古い未処理候補がある場合と、今回対象が51文書の場合のrequest specを追加する。

### [MAJOR]-2 設計で明記された整合性境界の結合テストが不足している
- 箇所: `spec/services/imports/applier_spec.rb:74`、`spec/services/imports/concurrency_spec.rb:19`・`:47`、`spec/requests/credit_card_unpaids_spec.rb:33`、`spec/requests/shift_credit_card_payment_due_on_spec.rb:17`
- 根拠: 詳細設計§10は「編集・支払済・due override・削除のcallback」と、Guard 0行から「同じ候補の同時承認は取引1件」を検証対象として明記する。
- 問題: 既存の支払済・支払予定日変更request specにはImportEntryがなく、conflict・履歴を検証しない。同時承認specは候補作成時にGuardを作成するため、Guard 0行からの承認競合を通らない。
- 修正方針: 取込済み取引に対する支払済・支払予定日変更のrequest specで取引変更とconflict・前後eventを確認する。候補準備後Guardを0行にし、競合後Guard1行・取引1件を両adapter・両構築方式で確認する。

RESULT: FAIL
