## 確認範囲
- GitHub Issue #65・#67・#68本文、詳細設計コメント6308861040
- 基点との差分・未追跡ファイル、関連controller・model・service・view・migration
- 分類・手動反映・訂正・並行処理の既存／追加spec
- 要件定義書・アプリケーション仕様書・操作削減検証
- 両DBの検証結果・全RSpecログ（テストは実行せず）

## 指摘
### MAJOR-1 カード引落候補をfeeへ変更すると新規支出を作成できる
- 箇所: `app/services/imports/candidate_validator.rb:13-19`
- 根拠: 13行目は確認済みのfee／transfer／investmentを許可する一方、原文種別を検査する18行目は変更後がnormalの場合に限定されている。`app/services/imports/applier.rb:107,130` はこの検証を通過すると実績を作成する。承認済み設計4.6はカード引落について「新規支出・振替・自動支払済を作らない」と規定している。
- 問題: `source_kind=card_settlement` の候補で、妥当な支出・銀行経路を指定して `transaction_kind=fee` として承認すると、通常の確認だけで新規支出が登録される。専用の種別訂正チェック・理由も不要で、既存のカード支払済処理と二重計上し得る。refund／cancellationも同様に、この条件を迂回できる。既存specはカード引落由来の予定昇格だけを拒否確認している（`spec/services/imports/classification_manual_spec.rb:69`）。
- 修正方針: 原文種別と変更後種別の組合せを検証し、card_settlement／refund／cancellation由来のfee／transfer／investmentによる新規作成を拒否する。専用確認と理由を伴うnormalへの訂正は維持し、approve／distinct等で迂回できない回帰specを追加する。

RESULT: FAIL
