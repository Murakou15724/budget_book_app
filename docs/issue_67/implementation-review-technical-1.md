## 確認範囲
- GitHub Issue #67・#65本文、承認済み詳細設計コメント6262287659
- 基点833c3f43との差分、Git状態、未追跡の実装・spec
- `app/models/import_*.rb`、`app/models/concerns/import_target_tracking.rb`
- `app/services/imports/`、画像取込Service・Controller、取引Controller・モデル
- 取込関連画面・helper、マスタ削除制限、routes・ログフィルタ
- `db/migrate/20261019000002_create_import_tracking.rb`、`db/schema.rb`
- 取込関連model・service・request spec、並行実行用support
- `docs/アプリケーション仕様書.md`
- 提示された両DBの実行ログ：各227 examples、0 failures、8 pending。テストの追加実行なし。schemaロード構築の検証結果は未提示

## 指摘
### [MINOR]-1 個別却下すると文書の絞り込みが失われる
- 箇所: `app/views/image_import_drafts/index.html.erb:111`
- 根拠: 個別却下リンクは`batch_id`だけを引き継ぐ。画像取込後の遷移は`app/controllers/image_imports_controller.rb:19`で`document_ids`を使用し、却下後は`app/controllers/image_import_drafts_controller.rb:41`で受信した絞り込みへ戻る。
- 問題: アップロード後や文書詳細から開いた一覧で個別却下すると、`document_ids`が失われ、全体の最新50文書へ移動する。続けて確認する候補が別の取込分へ切り替わる。
- 修正方針: 個別却下リンクにも`document_ids`を引き継ぐ。絞り込んだ一覧からリンク経由で却下し、残りの対象文書と候補が維持されるrequest specを追加する。

### [MINOR]-2 画像番号がアップロード順と一致しない
- 箇所: `app/controllers/image_import_drafts_controller.rb:3`、`app/views/image_import_drafts/index.html.erb:5`
- 根拠: 文書をid降順で取得し、その表示順に「画像1」「画像2」を付けている。一方、`app/services/imports/image_receiver.rb:18`では送信順の番号でエラーを通知する。
- 問題: 画像A・Bを順に送信すると、通常はBが「画像1」、Aが「画像2」と表示される。途中に形式エラーや既存文書の再送がある場合も番号がずれ、エラー通知と解析結果で同じ画像番号が別の入力を指す。
- 修正方針: 受付時の画像番号とDocumentの対応を結果表示まで保持し、その番号を表示する。複数画像の送信順、途中の形式エラー、既存画像の再送を含む表示specを追加する。

RESULT: FAIL
