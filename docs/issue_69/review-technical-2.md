## 確認範囲
- Issue #69 本文・詳細設計コメント `6517586990`
- 関連Issue #66/#67/#68、各関連設計・取得方式調査資料
- PayPay公式CSVヘルプ・取引履歴の種類
- `app/services/imports/` の記録・分類・照合・反映・確認署名・訂正処理
- 取込関連モデル、マスタモデル、`db/schema.rb`、既存migration
- 取込履歴・未処理候補のcontroller/view、関連service/request spec、並行検証ヘルパー
- `Gemfile.lock`、Rails 7.1.6・Rack 3.2.6のフォーム解析処理
- テストは設計フェーズのため未実施との提示を確認。レビュー中も実行していない

## 指摘
### [MAJOR]-1 共通承認一覧の行数制御がなく、CSV上限内でも承認フォームが送信不能になる
- 箇所: 詳細設計第5.4章・第6章・第10章T9。「100行単位」の制御対象が文書showに限られ、既存未処理候補一覧は原文表示の追加だけになっている。
- 根拠: `app/controllers/image_import_drafts_controller.rb:16` は50文書単位で制限する一方、同`:20` は各文書の未処理候補を全件取得する。`app/views/image_import_drafts/index.html.erb:29` の単一フォーム内で、同`:43` 以降が全候補について日付・種別・分類・口座・金額などの入力欄を生成する。`Gemfile.lock:175` のRack 3.2.6は、URLエンコードされたフォームのパラメータ数を既定4,096個に制限する。[Rackの上限実装](https://github.com/rack/rack/blob/v3.2.6/lib/rack/query_parser.rb#L53)、[フォーム解析処理](https://github.com/rack/rack/blob/v3.2.6/lib/rack/request.rb#L481)
- 問題: 承認必須で1,000行のCSVを取り込むと、この共通一覧は1,000行分の編集値を送信するため、少数行だけ選択してもパラメータ上限を超え、承認・日付一括プレビューがcontroller到達前に拒否される。複数文書では表示件数と原文payloadの取得量もさらに増える。文書showのページングでは防げない。
- 修正方針: `ImageImportDraftsController#index` も変更対象に含め、候補の取得・描画・フォーム送信を100行などの単位に制限するか、CSVはページング済みの専用確認導線へ分岐する。履歴一覧の全行preloadも併せて制限する。T9に、1,000行および複数CSVを共通一覧から確認し、実際のURLエンコード形式で承認・日付プレビューを送信できるrequest検証を追加する。

RESULT: FAIL
