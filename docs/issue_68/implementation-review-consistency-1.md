## 確認範囲

- GitHub Issue #68本文、親Issue #65本文、依存Issue #67本文
- 承認済み詳細設計コメント `6308861040`
- `git diff 2b0628b34f71c75e2c0b570aa5a29630327d70fb`、`git status --porcelain`、未追跡の追加実装・spec
- 分類ルール、候補検証、自動反映、日付一括指定、実績訂正のmodel/service/controller/view
- migration、schema、関連する既存・追加spec
- `docs/要件定義書.md`、`docs/アプリケーション仕様書.md`
- 提示されたMySQL/PostgreSQLのmigration構築後RSpecログ（各302 examples、0 failures、8 pending）
- 検証用 `verify_migration.rb`、`measure_operations.rb`。テスト・DB操作は実行していない

## トレーサビリティ

| 要求 | 設計節 | 実装箇所 | テスト |
|---|---|---|---|
| AC1 範囲付き再利用・明示的なルール作成 | 4.1、5.1 | `app/services/imports/rule_writer.rb:13`、`rule_resolver.rb:5` | `classification_spec.rb`「元口座・source・収支・経路・取引先の完全一致だけを使う」、`confirmed_operations_spec.rb`のルール作成・再送 |
| AC2 有効状態・優先順位・理由・競合保留 | 4.2、5.2 | `app/services/imports/rule_resolver.rb:15`、`app/views/import_entries/_decision.html.erb:3` | `classification_spec.rb`「優先順位が異なり出力が同じでも複数一致は保留する」 |
| AC3 初期無効・二重の明示許可 | 4.3、5.3 | `db/migrate/20261021000001_add_import_classification.rb:3`、`rule_resolver.rb:41` | `classification_spec.rb`の設定4組合せ、`classification_concurrency_spec.rb`の停止後反映拒否 |
| AC4 候補の各種矛盾を阻止 | 4.4、5.4 | `app/services/imports/candidate_validator.rb:37`、`applier.rb:139` | `classification_spec.rb:142`、`:157`。設計T5の一部が欠落 |
| AC5 日付未確定・出典・一括確認 | 4.5、5.5 | `app/services/imports/strict_date.rb:15`、`bulk_date_update.rb:6` | `classification_spec.rb`の日付境界、`confirmed_operations_spec.rb:15`〜`:59` |
| AC6 特殊取引を区別し推測処理しない | 4.6、5.4 | `app/services/imports/transaction_kind_classifier.rb:11`、`candidate_validator.rb:9`、`applier.rb:147` | `classification_spec.rb:117`の自動反映拒否。手動解決の必須検証が欠落 |
| AC7 自動成功の件数・方向別金額・適用ルール | 5.6 | `app/services/imports/applier.rb:132`、`app/views/import_documents/_summary.html.erb:15` | `classification_spec.rb:128`、`import_classification_spec.rb:69` |
| AC8 将来のみの変更・別操作による実績訂正 | 5.3、5.7 | `app/services/imports/transaction_correction.rb:7`、`rule_resolver.rb:41` | `confirmed_operations_spec.rb:89`以降、`classification_spec.rb:84`、`:128` |
| AC9 境界・停止・再実行の検証 | T1〜T12 | 上記実装、`db/migrate/20261021000001_add_import_classification.rb:1` | 分類・確認操作・並行spec、既存取込spec。必要な検証と最新結果に不足あり |
| 親#65 操作削減の導入前後比較 | 10章末尾 | 自動反映導線、検証用 `measure_operations.rb` | 指定成果物 `docs/issue_68/操作削減検証.md` が未作成 |

## 指摘

### [MAJOR]-1 許可条件を満たす移動予定も実績化できない

- 箇所: `app/services/imports/applier.rb:147`
- 根拠: 詳細設計5.4は「transfer/investmentの予定は元候補で利用者が確認した移動種別と一致し、4.4の移動先・経路条件を満たす場合だけ実績化できる」と規定。実装は147〜149行でその条件を確認した後、151行で原文種別がnormal以外なら無条件に拒否する。
- 問題: 原文がtransferで、利用者が移動種別・移動先・経路を確認しても、正常な移動予定を対応付けて実績化できない。
- 修正方針: 確認済みtransfer/investmentの許可条件を原文種別の判定にも反映する。カード引落・返金等の禁止を維持し、正常な移動予定の実績化と禁止対象の拒否を検証する。

### [MAJOR]-2 不正な対応先予定の理由と修正導線が利用者へ返らない

- 箇所: `app/services/imports/applier.rb:146`、`app/controllers/import_entries_controller.rb:34`
- 根拠: 詳細設計5.4は、不正予定へのlinkで「invalid_planned_target と個別理由」を返し、「対象予定を修正するリンク」を表示することを要求。実装は算出した個別理由を152行で捨て、controllerもresult.reasonを使わず、69〜72行の共通保留文言だけを表示する。
- 問題: 候補・予定・イベントを変更しない点は満たすが、利用者は失敗した予定の具体的な問題と修正先を確認できない。追加した日本語理由もこの経路では表示されない。
- 修正方針: 無更新のまま対象予定IDと個別理由を結果へ含め、画面へ表示し、対象予定の編集リンクを設ける。request specで失敗理由・修正リンク・無更新を確認する。

### [MAJOR]-3 設計で必須とした手動解決・予定検証のテストが不足している

- 箇所: `spec/services/imports/classification_spec.rb:117`、`:142`、`:157`
- 根拠: 詳細設計T7は「手動transfer/feeは要件を満たして登録」、T5は予定の「現金方法＋銀行口座／不正クレカ状態／移動先欠落」を必須検証としている。現状の特殊取引specは自動拒否のみで、予定の不正検証はカテゴリ区分不一致の1例のみ。
- 問題: 新たに設けた手動の特殊取引解決、種別訂正の確認・理由ゲート、予定そのものの支払経路検証を確認できない。通常の手入力用transfer/investment specでは取込固有の検証を通らない。
- 修正方針: 取込経路でのtransfer/fee成功、必要条件欠落の拒否、特殊→normal訂正のチェック・理由必須、予定対象の経路・クレカ状態・移動先の正常／異常ケースを追加する。各拒否では実績・候補・イベントの無変更も確認する。

### [MAJOR]-4 操作削減の実測成果物が欠落している

- 箇所: `docs/issue_68/操作削減検証.md`（未作成）
- 根拠: 親Issue #65の共通受入条件と詳細設計10章末尾は、同じ代表シナリオの導入前後5指標を実測し、このファイルへ保存することを要求している。
- 問題: 10件自動反映のservice specと実測用スクリプトはあるが、入力回数・再選択項目数・取得／アップロード回数・承認件数・必要画面数の比較結果と初回設定の別表がない。
- 修正方針: 同じ画像・初期マスタで基点mainと導入後を測定し、5指標、初回設定、対象外経路、残る取得・アップロード操作を指定ファイルへ記録する。

### [MAJOR]-5 最新成果物と両DB構築について必須検証が完了していない

- 箇所: 詳細設計10章T12、`spec/services/imports/confirmed_operations_spec.rb:49`
- 根拠: 詳細設計はMySQL/PostgreSQLそれぞれmigration構築・schema構築で全RSpec成功を要求。提示ログはmigration構築後の各302 examplesのみで、依頼文にも100件rollbackテスト・設定context変更は再実行待ち、schema構築は手動DB操作待ちとある。
- 問題: 既存ログは現在の変更後の検証結果ではなく、両DBのschema構築からの動作も未確認である。必須検証の成功条件を満たしていない。
- 修正方針: 許可された専用DBで必要な構築を完了後、現在の成果物に対し両DB・両構築方式の全RSpecを実行し、結果を保存する。既存値保持・DDL途中再開の検証結果も併記する。

RESULT: FAIL
