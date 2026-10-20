## 確認範囲
- GitHub Issue #67本文、承認済み詳細設計コメント6262287659
- `app/services/imports/`、取込関連モデル・Controller・View・Helper
- Transactionの変更・削除callback、既存呼出し元、マスタ削除制限
- `db/migrate/20261019000002_create_import_tracking.rb`、`db/schema.rb`
- 取込関連model・service・request・並行処理spec
- 提示されたMySQL／PostgreSQLの実行ログ：各255 examples、0 failures、8 pending

## 指摘
### MAJOR-1 既存候補の移行とDB再構築の検証が完了していない
- 箇所: `db/migrate/20261019000002_create_import_tracking.rb:99`、`spec/services/imports/concurrency_spec.rb:50`
- 根拠: migrationの99〜114行は既存候補から文書・Entry・eventを作成して参照を設定する。並行specの50行以降はGuardを削除して初期状態を模擬している。メインCodexから、再構築検証用の比較処理を修正した後の再実行は未実施と報告されている。
- 問題: 通常RSpecの成功だけでは、既存候補の保持、移行再実行時の重複防止、実際のmigration／schemaロード後の初回保存を確認できない。修正版による両DBの検証結果は未提示であり、データ移行部分の検証に実質的な欠落が残る。
- 修正方針: 専用の使い捨てDBで、修正版の再構築検証をMySQL／PostgreSQL双方について完了する。旧候補・既存取引の保持、再実行、制約、schemaロード後のGuard初期化・並行承認について成功結果を提示する。

RESULT: FAIL
