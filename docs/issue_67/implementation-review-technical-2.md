## 確認範囲
- GitHub Issue #67・#65本文、承認済み詳細設計コメント6262287659
- 基点833c3f43からの差分、Git状態、未追跡の実装・spec
- 取込関連モデル・Service・Controller・View、Transactionの書込み経路
- migration、db/schema.rb、関連spec、アプリケーション仕様書
- MySQL／PostgreSQLのmigration・schema構築後のテストログ、最新の全RSpec各251 examples・0 failures・8 pending
- Rails 7.1.6のReferenceDefinition実装（テストは実行せず）

## 指摘
### MAJOR-1 MySQLで参照カラム追加後に移行が中断すると、再実行で制約が欠落する
- 箇所: `db/migrate/20261019000002_create_import_tracking.rb:68`
- 根拠: `add_reference`全体を`unless column_exists?`で囲んでいる。Rails 7.1.6の`abstract/schema_definitions.rb:216–226`では、カラム追加・index追加・FK追加を別々に実行する。
- 問題: MySQLでカラム追加後、indexまたはFK追加前に処理が中断すると、カラムだけが残る。再実行では68行目全体をスキップし、unique indexやFKがない状態でmigrationが完了する。正常完了後の再実行検証では、この中断経路を検出できない。
- 修正方針: カラム・unique index・FKの存在確認と追加をそれぞれ独立させる。カラムのみ存在する状態、およびカラムとindexだけ存在する状態から再実行し、全制約が復旧することを検証する。

RESULT: FAIL
