## 確認範囲

- Issue #67 本文、詳細設計コメント `6262287659`
- 関連Issue #65 / #68 / #69 / #70 / #71 / #76 / #77
- `/home/murakamiko/projects/AGENTS.md`、Reviewer共通ルール
- `app/models/{transaction,image_import_draft,account,category,payment_method,setting,account_reconciliation}.rb`
- `app/controllers/{transactions,image_imports,image_import_drafts,categories,accounts,payment_methods}_controller.rb`
- `app/services/image_import_draft_builder.rb`、`app/services/gemini/transaction_extractor.rb`
- `db/schema.rb`、`db/seeds.rb`、`config/routes.rb`、ログフィルタ設定
- 画像取込の既存service/request spec、`spec/rails_helper.rb`
- 既存取引更新rake、旧データ移行処理、`docs/アプリケーション仕様書.md`
- Rails 7.1.6 の `Migration.maintain_test_schema!`、`DatabaseTasks#load_schema` の実装
- 設計フェーズのためテスト未実行

## 指摘

### [MAJOR]-1 schemaから構築したDBで共通排他行が存在しない

- 箇所: 第3節 ImportGuard、第6.3節、第7節、第10節
- 根拠: 設計は初期行について「migrationで `name=ledger` を1行作成」と規定し、通常のTransaction書込みにもGuard取得を必須としている。一方、`db/schema.rb:5` は `db:schema:load` によるDB構築を前提とし、`spec/rails_helper.rb:31` もschema準備を使用する。Rails 7.1.6 の `DatabaseTasks#load_schema` はschemaファイルを読み込む処理であり、migration内のデータ作成は実行しない。設計の対象ファイル・初期化方針には、この経路でGuard行を確保する処理がない。
- 問題: 新規環境や再構築したテストDBにはGuardテーブルだけが存在し、排他対象の行がない。既存行を取得する実装では通常の取引保存まで失敗し、空の検索結果を許容する実装では排他が成立しない。既存DBへのmigration適用だけでは発見できない。
- 修正方針: `ImportGuard.synchronize` でunique制約と競合処理を用いて必要行を安全に確保してからロックするなど、migrationのデータ投入に依存しない初期化方式を明記する。schemaから構築した専用DBで、最初の通常取引保存と初回並行実行を検証する方針を追加する。

RESULT: FAIL
