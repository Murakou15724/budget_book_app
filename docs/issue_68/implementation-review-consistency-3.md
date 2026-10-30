## 確認範囲

- GitHub Issue #68本文、承認済み詳細設計コメント `6308861040`、関連Issue #65・#67。
- 基点 `2b0628b34f71c75e2c0b570aa5a29630327d70fb` からの差分、Git状態、未追跡の新規実装・spec。
- 分類ルール、候補検証、自動反映、一括日付指定、実績訂正のModel・Service・Controller・View。
- migration・schema、新規分類関連spec、既存取込specの変更。
- 要件定義書・アプリケーション仕様書、操作削減資料・計測スクリプト、両DBの検証証跡。テストは実行していない。

## トレーサビリティ

| 要求 | 設計節 | 実装箇所 | テスト |
|---|---|---|---|
| AC1 範囲付き再利用・明示的ルール作成 | 4.1、5.1 | `app/services/imports/rule_writer.rb:13`、`app/services/imports/rule_resolver.rb:5` | `confirmed_operations_spec.rb`「ルール作成は明示選択のみ…」、`classification_spec.rb`「元口座・source・収支・経路…」 |
| AC2 有効状態・範囲・優先順位・競合理由 | 4.2、5.2 | `app/services/imports/rule_resolver.rb:17`、`app/views/import_classification_rules/index.html.erb:7` | `classification_spec.rb`「優先順位が異なり出力が同じでも複数一致は保留する」 |
| AC3 初期無効・一般承認設定・経路許可 | 4.3、5.3 | `db/migrate/20261021000001_add_import_classification.rb:3`、`app/services/imports/rule_resolver.rb:43` | `classification_spec.rb` 設定4組合せ、`classification_concurrency_spec.rb` 設定停止commit後の拒否 |
| AC4 日付・金額・分類・支払経路の整合性 | 4.4、5.4 | `app/services/imports/candidate_validator.rb:45`、`app/services/imports/applier.rb:139` | `classification_spec.rb`「カテゴリ・口座・支払方法の不整合…」、`classification_manual_spec.rb` 予定自身の不整合 |
| AC5 日付出典・未確定・一括確認 | 4.5、5.5 | `app/services/imports/strict_date.rb:15`、`app/services/imports/bulk_date_update.rb:6` | `classification_spec.rb` 厳密日付、`confirmed_operations_spec.rb` 一括指定・rollback・再送 |
| AC6 特殊取引の区別・推測処理禁止 | 4.6 | `app/services/imports/transaction_kind_classifier.rb:4`、`app/services/imports/candidate_validator.rb:17` | `classification_manual_spec.rb` 特殊由来の登録拒否・手動移動・手数料。未払画面への案内は欠落 |
| AC7 自動成功の閲覧・保留だけ確認 | 5.6 | `app/views/import_documents/_summary.html.erb:15`、`app/views/image_import_drafts/index.html.erb:15` | `classification_spec.rb` 自動10件、`import_classification_spec.rb` 全件自動成功表示 |
| AC8 将来へのルール変更・反映後訂正 | 5.7、T9/T10 | `app/services/imports/transaction_correction.rb:7`、`app/services/imports/rule_resolver.rb:49` | `confirmed_operations_spec.rb` 訂正snapshot一致・他候補conflict・設定変更拒否 |
| AC9 境界条件・停止・再実行の検証 | T1〜T12 | 上記サービス、`db/migrate/20261021000001_add_import_classification.rb:1` | 分類・並行・既存取込spec、両DB検証ログ。下記の必須テストが不足 |
| 親#65 操作削減の比較 | 10 | `docs/issue_68/検証スクリプト/measure_operations.rb:71` | `operations-before.json`／`operations-after.json`、操作削減検証.md |

## 指摘

### [MAJOR]-1 確認履歴からのルール作成に必要な拒否条件のテストが不足

- 箇所: `spec/services/imports/confirmed_operations_spec.rb:62`、`spec/requests/import_classification_spec.rb:60`
- 根拠: 設計5.1は保存時の元候補・実績snapshot再検証を要求し、T2は「未反映」「期限切れ」等を必須検証としている。現在のspecは作成成功・未確認checkbox・nonce再送・内容差替えを検証している。
- 問題: 未反映候補からの作成、フォーム発行後の元実績変更／削除、作成tokenの期限切れによってルールが作成されないことを確認できない。既存の期限切れspecは別の `ReviewToken` が対象。
- 修正方針: 実Modelを使い、各拒否条件でルール・イベントが増えないspecを追加する。

### [MAJOR]-2 Geminiへの新schema・prompt送信を検証する必須テストがない

- 箇所: `spec/services/gemini/transaction_extractor_spec.rb:19`
- 根拠: 設計8章は「schema/promptはローカルのモックHTTPで検証」、10章はExtractorの既存spec更新を要求する。実装変更は `app/services/gemini/transaction_extractor.rb:22`・`:101` にある。
- 問題: 現在のExtractor specは旧必須3キーによる応答形式の検査のみ。merchant・原文日付・特殊種別・根拠・不確実性を実際のHTTPリクエストで要求していることが未検証。
- 修正方針: モックHTTPで送信bodyを検査し、新schemaと年補完禁止・特殊取引を区別する指示を確認する。

### [MINOR]-3 カード引落候補から既存の未払画面への案内がない

- 箇所: `app/views/import_entries/_decision.html.erb:1`、`app/views/import_entries/show.html.erb:8`
- 根拠: 設計4.6のcard_settlementは「常に保留。既存のクレカ未払画面へ案内」と規定している。
- 問題: 種別と一般的な保留理由は表示するが、取込画面には未払画面への案内がない。利用者が次の処理先を探す必要がある。
- 修正方針: カード引落由来の候補に、既存のクレカ未払い一覧への説明とリンクを表示し、request specで確認する。

### [MINOR]-4 日付一括指定の再送結果で確定日付が空欄になる

- 箇所: `app/services/imports/bulk_date_update.rb:24`、`app/views/import_draft_dates/preview.html.erb:6`
- 根拠: 設計5.5は「変更結果と件数・対象リンクを表示」「nonceイベントで二重送信は既存結果へ案内」と規定している。
- 問題: 再送時のResultには `after` が設定されず、結果画面の「→ 新日付」が空欄になる。現行の再送specはstatusとイベント件数のみを確認している。
- 修正方針: 再送でも確定済み日付を返すか、保存済み結果を明示する表示にし、二重送信時の結果画面を検証する。

RESULT: FAIL
