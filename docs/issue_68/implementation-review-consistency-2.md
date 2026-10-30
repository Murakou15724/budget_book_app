## 確認範囲
- GitHub一次情報: Issue #68・親Issue #65・依存Issue #67本文、承認済み詳細設計コメント6308861040（仕様節1〜11）。
- `git diff 2b0628b34f71c75e2c0b570aa5a29630327d70fb`、`git status --porcelain`、未追跡の新規アプリ・specファイル。
- 分類ルール、共通検証、自動反映、一括日付、実績訂正のmodel/service/controller/view、migration・schema。
- 新規分類spec、既存Applier・Receiver・並行・Extractor・履歴関連spec。
- 要件定義書・アプリケーション仕様書、操作削減検証・計測スクリプト・JSON、両DBのmigration検証JSONと全4条件の最終RSpecログ。各317 examples / 0 failures / 8 pendingを確認。テスト・DB操作は実行していない。

## トレーサビリティ
- AC1 範囲付き再利用・明示作成 → 4.1・5.1 → `app/services/imports/rule_writer.rb:13`、`rule_resolver.rb:5` → `classification_spec`「元口座・source・収支・経路・取引先の完全一致だけを使う」、`confirmed_operations_spec`「ルール作成は明示選択のみでnonce再送と内容差替えを区別する」。
- AC2 有効状態・優先順位・複数一致保留 → 4.2・5.2 → `app/services/imports/rule_resolver.rb:17`、`app/views/import_entries/_decision.html.erb:6` → `classification_spec`「優先順位が異なり出力が同じでも複数一致は保留する」。
- AC3 初期無効・二重許可 → 4.3・5.3 → `db/migrate/20261021000001_add_import_classification.rb:3`、`app/services/imports/rule_resolver.rb:43` → 設定4組合せspec、migration検証。設定停止の並行検証に不足あり（指摘2）。
- AC4 共通整合性 → 4.4・5.4 → `app/services/imports/candidate_validator.rb:39`、`applier.rb:100`・`:139` → `classification_spec`「カテゴリ・口座・支払方法の不整合と不正amountをmanualでも拒否する」、予定実績化の各spec。
- AC5 日付出典・一括確認 → 4.5・5.5 → `app/services/imports/strict_date.rb:6`、`bulk_date_update.rb:6` → strict日付・0/100/101件・stale・rollbackの各spec。異常時HTTP仕様に不一致あり（指摘3）。
- AC6 特殊取引の区別・精算等を推測しない → 4.6 → `app/services/imports/transaction_kind_classifier.rb:3`、`candidate_validator.rb:11` → 特殊語・手動transfer/fee・予定昇格拒否spec。新規作成経路に漏れあり（指摘1）。
- AC7 自動成功の閲覧・保留だけ承認 → 5.6 → `app/services/imports/applier.rb:132`、`app/views/import_documents/_summary.html.erb:15` → `classification_spec`「自動反映10件を個別承認せず確定イベントから集計でき、再実行とルール変更でも不変」、自動成功画面spec。
- AC8 将来だけルール適用・別操作で実績訂正 → 5.3・5.7・9 → `app/services/imports/transaction_correction.rb:7`、`rule_resolver.rb:43` → 訂正snapshot一致・他候補conflict・設定変更・paid訂正spec。訂正確認後のrule変更検知に不一致あり（指摘4）。
- AC9 境界条件・再実行 → T1〜T12 → 分類サービス群、`app/services/imports/applier.rb:36` → 新規分類spec・既存#67回帰spec。自動／手動競合の検証に不足あり（指摘2）。
- 既存値保持・両DB構築 → 7・T12 → `db/migrate/20261021000001_add_import_classification.rb:2` → migration検証JSON、MySQL/PostgreSQL×migration/schemaの全4ログ。
- 親#65の操作削減比較 → 10 → `docs/issue_68/検証スクリプト/measure_operations.rb:1` → `操作削減検証.md`、`operations-before.json`・`operations-after.json`。5指標と初回設定を別計上。

## 指摘

### [MAJOR]-1 カード引落・返金由来の候補を別の特殊種別に変更すると新規登録できる
- 箇所: `app/services/imports/candidate_validator.rb:13`、`:17`、`app/services/imports/applier.rb:100`。
- 根拠: 詳細設計4.6はcard_settlementを「常に保留」「新規支出・振替…を作らない」、refund/cancellationも「常に保留」とする。専用確認と理由による例外はnormalへの種別訂正として規定されている。
- 問題: 手動確認済みのfee/transfer/investmentは許可され、source_kindの制限は変更後kindがnormalの場合だけである。カード引落由来をtransferへ変更し、移動先等を満たすと、専用訂正確認なしで新規振替を作成できる。予定昇格には拒否specがあるが、新規作成にはない。
- 修正方針: 新規作成でも原文種別に応じた許可範囲を検証する。card_settlement/refund/cancellation由来からtransfer/fee等への変更を拒否し、設計で許容したnormalへの明示訂正と区別する。approve/distinct/adopt_revisionの回帰specを追加する。

### [MAJOR]-2 必須とされた設定停止・自動／手動競合の並行specがない
- 箇所: `spec/services/imports/classification_concurrency_spec.rb:18`・`:27`、`spec/services/imports/concurrency_spec.rb:19`。
- 根拠: T4は「設定OFFの並行commit」、T11は「自動と手動同時」を必須検証としている。
- 問題: 新規並行specの停止対象はルールのみ。既存並行specはapprove同士等であり、一般設定／source許可の停止とauto_applyの競合、および同じ候補へのauto_applyとapproveの競合を検証していない。
- 修正方針: 一般設定・source許可それぞれの停止commit後に自動反映されないこと、同じ候補の自動／手動同時処理で取引と確定イベントが1件になることを、既存の独立connection・Queue方式で検証する。

### [MINOR]-3 一括日付指定の入力不正が設計の422ではなく302になる
- 箇所: `app/controllers/import_draft_dates_controller.rb:4`。
- 根拠: 詳細設計5.5は、処理済み・参照・conflict混入、存在しないID、不正日付、100件超を「全体を422」と規定している。
- 問題: previewの該当エラーはすべてredirectとなる。サービスspecでは例外を確認しているが、HTTPの異常系specがなく、この不一致を検出できない。
- 修正方針: 対象の入力不正を422で表示し、代表的な不正入力についてHTTP statusと全件無更新をrequest specで確認する。

### [MINOR]-4 実績訂正tokenがプレビュー後のルール変更を検知しない
- 箇所: `app/services/imports/transaction_correction.rb:13`・`:31`。
- 根拠: 詳細設計9は「プレビュー後の…rule変更」を無更新で再確認へ送ると規定する。
- 問題: 訂正tokenと再検証には対象snapshot、関連候補version、締め日・支払日しか含まれない。関連ルールを停止・変更してもこれらが変わらなければ旧プレビューで訂正できる。該当specも設定変更だけを扱っている。
- 修正方針: 関連ルールのID/versionを確認contextに保持して再検証し、プレビュー後のルール変更時に実績・候補・イベントが無更新となるspecを追加する。

RESULT: FAIL
