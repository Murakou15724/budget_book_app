## 確認範囲
- GitHub Issue #69本文、詳細設計コメント `6517586990`、`docs/issue_69/詳細設計.md`
- 関連Issue #66/#67/#68、origin/mainの各調査資料・詳細設計
- `app/services/imports/{entry_recorder,fingerprint,image_receiver,rule_resolver,matcher,applier}.rb`
- `app/services/imports/{candidate_validator,candidate_confirmation,transaction_kind_classifier,rule_writer,review_token,operation_token}.rb`
- `app/models/{import_source,import_document,import_identity,import_entry,import_event,image_import_draft,import_classification_rule,import_guard,account,payment_method}.rb`
- `app/models/concerns/import_configuration_guard.rb`、取込関連Controller・View
- `db/schema.rb`、`db/migrate/20261019000002_create_import_tracking.rb`
- 既存EntryRecorder・分類spec、`spec/support/import_concurrency.rb`（参照のみ。テスト未実行）
- PayPay公式CSVヘルプ、MySQL公式資料・JSONパーサ実装

## 指摘

### [MAJOR]-1 許容する取引番号の長さが既存TEXT列の容量を超える
- 箇所: 詳細設計第4.2章「取引番号」、第7章。
- 根拠: 第4.2章は「入力の8MiB上限内で桁数の独自打切りをしない」とする。一方、`db/schema.rb:209`、`db/migrate/20261019000002_create_import_tracking.rb:31` は `external_id` を通常のtext列とし、`app/services/imports/entry_recorder.rb:17` で原文をそのまま保存する。MySQLのTEXT上限は65,535 bytesである。[MySQL公式資料](https://dev.mysql.com/doc/refman/8.0/en/storage-requirements.html)
- 問題: 例えば65,536文字のASCII取引番号は設計上有効だが、MySQLではidentity保存に失敗する。候補一括保存transactionがrollbackし、同じCSVの正常行も処理できない。
- 修正方針: 8MiB以内の番号を無損失保存する契約に合わせ、既存 `external_id` の容量拡張を新規migration・schema・対象ファイルへ明記する。65,535/65,536 bytesとマルチバイト番号について、正常行との混在・再送を両DBで検証する。

### [MAJOR]-2 任意精度の金額をJSONへ保存する表現が未定義
- 箇所: 詳細設計第4.2章「円金額」、第10章T3/T8。
- 根拠: 第4.2章はInteger化した「パース可能な任意精度整数」をpayloadへ保持するとする。保存先は `db/schema.rb:170` のJSON列で、`app/services/imports/entry_recorder.rb:23` が直接保存する。MySQLのJSONパーサは64bit範囲を超える整数をdoubleへ変換し、double範囲外はエラーにする。[MySQLのパーサ実装](https://github.com/mysql/mysql-server/blob/8.0/extra/rapidjson/include/rapidjson/reader.h#L1412-L1442)、[JSON読込実装](https://github.com/mysql/mysql-server/blob/8.0/sql-common/json_dom.cc#L519-L534)
- 問題: RubyのIntegerをJSON数値として保存すると、例えば `18446744073709551617` は精度を失い、400桁の正整数は保存に失敗する。draft.amountをnilにしても回避できず、不正金額行だけを保持して正常行を継続する設計と矛盾する。
- 修正方針: 範囲外金額の解析値は正規化した十進文字列として保存するなど、DBに依存しない表現を明記する。既存 `Fingerprint.source_payload` のInteger化も考慮し、保存後の再読込・digest・結果集計まで無丸めになる契約とする。64bit超・double範囲超の金額と正常行を混在させ、両DBで保存・再送を検証する。

RESULT: FAIL
