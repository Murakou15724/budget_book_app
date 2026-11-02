## 確認範囲
- GitHub Issue #69本文、承認済み詳細設計コメント6517586990
- 基点81123faからの実装差分、Git状態、未追跡の実装・spec
- CSV Parser／Receiver／Summary／SourceRoute
- 共通の候補保存・分類・反映・署名・訂正・競合制御
- 支払経路・分類ルールのモデル、controller、画面
- 候補一覧・文書履歴のページングと集計
- 新規migration、schema、検証スクリプト
- CSV関連spec、既存classification_concurrency_spec、提示されたテスト結果
- 取込条件資料、共通・案件チェックリスト

## 指摘
### [MAJOR]-1 MySQLの既知の競合spec失敗と両DBの検証が未解決
- 箇所: `spec/services/imports/classification_concurrency_spec.rb:18`、`app/models/import_guard.rb:3`
- 根拠: 提示結果ではMySQL migration後に同一nonce並行送信のspecが`ActiveRecord::RecordNotUnique`で失敗。現在の実装による再検証結果と、PostgreSQLを含む4条件の結果は未取得。
- 問題: 変更した排他制御で既知の失敗を解消できたことを確認できず、migrationとschemaロードの構築差による回帰も未検証。
- 修正方針: 用意した専用DBで両DB・両構築方法の全RSpecを実行する。同一nonce競合の失敗が再現する場合は原因を修正し、成功結果を保存する。

### [MINOR]-2 空ファイルがCSV入力エラーではなく保存失敗になる
- 箇所: `app/services/imports/csv_receiver.rb:19`
- 根拠: 長さ指定の`IO#read`は空ファイルで`nil`を返す。その値を渡された`paypay_csv_parser.rb:26`は`bytes.bytesize`で例外になり、Receiverの一般例外処理へ進む。`spec/requests/paypay_csv_import_spec.rb:58`は422だけを確認している。
- 問題: 空CSVでも「CSVが空です」へ到達せず、「保存できませんでした。履歴を確認し、再送してください」と誤った対処を案内する。
- 修正方針: 読込結果の`nil`を空文字列としてParserへ渡すか、`csv_empty`を返す。空のUploadedFileで理由表示と無保存を検証する。

RESULT: FAIL
