## 確認範囲
- GitHub Issue #68本文・承認済み詳細設計コメント6308861040
- 変更されたcontroller・model・service・view・routes
- 新規分類ルール・日付一括指定・実績訂正の実装と関連spec
- 新規migration・db/schema.rb・提示されたテスト証跡
- 共通AGENTS.md・reviewer-common.md

## 指摘
### MAJOR-1 Geminiへの指示が年付き日付も未確定にする
- 箇所: `app/services/gemini/transaction_extractor.rb:101`
- 根拠: promptは条件を付けず「date_year_explicitをfalseにしてください」と指示する。一方、`app/services/imports/strict_date.rb:16` はtrueの場合だけ原文日付を採用する。
- 問題: 年まで明記された画像でも、指示に従った応答は日付未確定となり、正常取引を自動反映できない。既存Extractor specには新しい指示内容の検証がない。
- 修正方針: 原文に年が明記されている場合はtrue、年が欠落している場合はfalseと明示する。HTTPリクエストのprompt・schemaと、両場合の日付判定を検証するspecを追加する。

### MAJOR-2 承認失敗時の保存が日付の出典更新を迂回する
- 箇所: `app/services/imports/applier.rb:210`
- 根拠: `CandidateConfirmation.apply` は不正金額で例外を送出する（`candidate_confirmation.rb:16`）。その後の救済処理は`draft.update!(@attributes)`を直接実行する。draftは負数の保存を許可する（`app/models/image_import_draft.rb:29`）。
- 問題: 原文確定の日付を持つ候補に、変更日付と金額`"-1"`を送ると、承認は失敗するが変更日付と負数が保存される。この際、`date_origin`は`source`のままで、日付変更に伴う確認情報も更新されない。その後に金額だけ修正すると、利用者が変更した日付を原文由来として登録できる。
- 修正方針: 失敗時は候補値を維持するか、保存する変更にも共通の日付出典更新・変更記録を適用する。日付変更と不正金額を同時送信する回帰specで、失敗直後と再承認後の出典を検証する。

RESULT: FAIL
