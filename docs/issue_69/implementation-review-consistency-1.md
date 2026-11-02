## 確認範囲

- GitHub Issue #69本文、承認済み詳細設計コメント `6517586990`、関連Issue #66/#67/#68
- 基点 `81123fa8f054e2f5f1686cd242e34f06338c9737` との差分、Git状態、未追跡の実装・spec
- CSV parser/receiver/summary、支払経路、共通分類・照合・反映・署名処理
- 関連controller/view、migration、schema、追加spec、既存の履歴・分類・訂正spec
- `docs/issue_69/取込条件と検証データ.md`、要件定義書・アプリケーション仕様書の差分
- [PayPay公式CSVヘルプ](https://paypay.ne.jp/help/c0447/)
- 依頼文のテスト結果。レビュー側ではテスト未実行

## トレーサビリティ

| 要求 | 設計節 | 実装箇所 | テスト |
|---|---|---|---|
| 公式書式と架空データの明示 | §4、T1 | `app/services/imports/paypay_csv_parser.rb:8`、`docs/issue_69/取込条件と検証データ.md` | parser spec「accepts only the 13 exact distinct headers」 |
| 経路設定の再利用・複数口座への振分け | §5.1、T4 | `app/services/imports/source_route.rb:6`、`app/models/import_payment_route.rb:34` | receiver spec「automatically applies ten configured payments/income…」。request検証不足 |
| 日時・金額・番号・原文の無欠損保持 | §4.2、T3 | `app/services/imports/paypay_csv_parser.rb:82`、`db/schema.rb:211` | parser specの原文・整数・日時、receiver specの巨大額・長大ID |
| 通常収支の分類・自動反映・承認必須 | §4.3、§5.1、T5 | `app/services/imports/paypay_csv_parser.rb:119`、`app/services/imports/rule_resolver.rb:24` | receiver specの10件反映・許可設定・ルール一致。request検証不足 |
| 特殊・不明行の理由付き保留 | §4.3、T6 | `app/services/imports/paypay_csv_parser.rb:104`、`app/services/imports/matcher.rb:22` | parser spec「holds special, foreign, points…」、receiver specの特殊種別訂正 |
| 同一・期間重複・画像/手入力類似・訂正 | §5.3、T7/T11 | `app/services/imports/entry_recorder.rb:13`、`app/services/imports/matcher.rb:18` | receiver specの同版参照・訂正・類似、csv concurrency spec |
| 六区分の件数・方向別金額・行番号と理由 | §5.4、T9 | `app/services/imports/csv_summary.rb:8`、`app/views/import_entries/_csv_raw.html.erb:2` | csv summary spec、request specの原文・理由表示 |
| 全体不正の無反映・個別不正の継続・再送 | §4.1、§5.2/5.3、T2/T8 | `app/services/imports/csv_receiver.rb:19`、`:75` | request specの書式不正・混在再送、receiver specのrollback・途中失敗。失敗時request検証不足 |
| 空・見出しのみ・引用符・金額・日時・月境界等 | §4、§9、T2/T3 | `app/services/imports/paypay_csv_parser.rb:25` | parser specのサイズ・行数・金額・日時境界 |
| 候補100件上限・実フォーム送信 | §5.5、T9 | `app/controllers/image_import_drafts_controller.rb:19`、`:70` | request spec「paginates 1,000 rows and 100 candidates…」 |
| 確認画面で識別用元口座と行の反映先を区別 | §6 | `app/views/import_draft_dates/preview.html.erb:4` に不足 | CSVの日付previewは成功のみ検証 |
| 両DBのmigration/schema構築と回帰確認 | §7、T12 | `db/migrate/20261030090000_add_paypay_csv_import.rb:2`、`db/schema.rb:209` | 必須4条件の成功結果が未提示 |

## 指摘

### [MAJOR]-1 両DB・4構築条件の必須検証が完了していない

- 箇所: 詳細設計§7、§10 T12および実行結果の保存要件
- 根拠: 設計は「MySQL・PostgreSQLのmigrationからの構築/schemaロードの双方」「4条件の全spec結果」の保存を必須としている。提示結果はMySQL schemaで403 examples・0 failures、MySQL migrationで403 examples・1 failure。PostgreSQLの結果と失敗解消後の全件結果は未提示。
- 問題: DB依存の保存容量・JSON精度・制約・競合処理を含む必須検証が未達で、実装完了条件を満たさない。
- 修正方針: 既知の1 failureを解消し、4条件で全RSpecを実行する。pendingの内訳、コマンド、結果を指定フォルダへ保存する。

### [MAJOR]-2 設計で必須としたrequest経由の受入検証が不足している

- 箇所: `spec/requests/paypay_csv_import_spec.rb:45`、`spec/services/imports/csv_receiver_spec.rb:7`
- 根拠: 詳細設計§10は「T2/T4/T5/T8/T9はrequest→DB/画面まで検証する」と明記。複数経路の10件反映、承認・CSV許可設定の組合せ、候補保存失敗・自動反映途中失敗は、現在はreceiver specで検証している。
- 問題: HTTP受付から複数経路の実績化、承認必須時の未実績、失敗時の警告・履歴表示までをつなぐ必須のテスト段が欠けている。
- 修正方針: 複数経路のCSV送信と設定別の実績件数、保存失敗・部分失敗後の画面とDB状態をrequest specで検証する。既存のサービス側の境界検証を重複させる必要はない。

### [MINOR]-3 CSVの日付一括確認画面に行の反映口座・支払経路が表示されない

- 箇所: `app/views/import_draft_dates/preview.html.erb:4`
- 根拠: 詳細設計§6は日付確認viewも対象とし「sourceアンカーと行口座の区別」を要求している。現状はCSVでも `import_source.account` を「元口座」として表示し、行の反映口座・取引方法を表示しない。
- 問題: 例えば識別用口座が銀行、行の反映先が残高・カードの場合でも銀行だけが表示され、複数経路の対象を確認できない。
- 修正方針: CSVでは識別用元口座と行の反映口座・取引方法を区別して表示し、異なる経路を含む日付previewの表示を検証する。

RESULT: FAIL
