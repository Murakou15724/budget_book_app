## 確認範囲
- Issue #68・親Issue #65・依存Issue #67本文、承認済み詳細設計コメント `6308861040`
- 基点 `2b0628b` との差分、Git状態、未追跡の新規アプリ・specファイル
- 分類・検証・反映・予定連携・一括日付・実績訂正のサービス、関連Model／Controller／View
- migration、schema、関連spec、提示された両DBのテストログ（各302 examples、0 failures、8 pending）
- `docs/要件定義書.md`、`docs/アプリケーション仕様書.md`

## 指摘

### [MAJOR]-1 MySQLで異なる取引先にルールが適用される
- 箇所: `app/services/imports/rule_resolver.rb:11`
- 根拠: merchant_keyをSQLの等価条件で照合している。`db/schema.rb:118` のルール表は `utf8mb4_0900_ai_ci` であり、アクセントを区別しない。一方、`app/services/imports/merchant_key.rb:8` の正規化ではアクセントを保持する。
- 問題: 正規化後も異なる `cafe` と `café` がMySQLでは一致する。片方の確認済みルールだけで他方の候補を分類・自動登録でき、PostgreSQLとも結果が異なる。
- 修正方針: DB検索後にもRubyで正規化キーの完全一致を確認するなど、DBの照合順序に依存しない一致判定にする。アクセント・濁点の異なる名称を両DBで検証する。

### [MAJOR]-2 原文で振替と判定した候補を予定へ連携できない
- 箇所: `app/services/imports/applier.rb:147`
- 根拠: 147〜149行は確認済みtransfer／investmentを許可するが、151行で `source_kind != "normal"` を一律拒否する。`app/services/image_import_draft_builder.rb:37` は原文の振替判定をsource_kindへ保存する。
- 問題: 原文が振替で、利用者が移動種別・移動先・経路を確認し、対応する振替予定も正常であっても、必ず `invalid_planned_target` になる。確認済み移動を許可する分岐が実際には機能しない。
- 修正方針: 確認済みtransfer／investmentと対象予定が一致する場合を、原文特殊種別の拒否条件から適切に除外する。正常な振替予定への連携成功と、不一致・未確認時の拒否を追加検証する。

### [MAJOR]-3 非クレカ候補の日付修正で不要な支払予定日が登録を妨げる
- 箇所: `app/services/imports/candidate_confirmation.rb:14`
- 根拠: `app/views/image_import_drafts/index.html.erb:117` は非クレカでも自動計算した支払予定日を送信する。CandidateConfirmationは日付変更後の計算値との一致だけでoverrideを除去し、`app/services/imports/candidate_validator.rb:62` は非クレカのoverrideを拒否する。
- 問題: 銀行・現金等の候補で、締め日をまたぐ日付修正を一覧から行うと、画面に残った変更前の支払予定日がoverrideとして保持される。支払予定日を操作していない正常な候補が `payment_route_mismatch` で登録できなくなる。
- 修正方針: 非クレカでは支払予定日のプリフィル値を送信しないようにする。日付変更時に未編集の自動計算値を明示overrideと誤認しない処理を整え、一覧フォーム経由の回帰specを追加する。

RESULT: FAIL
