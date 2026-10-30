## 確認範囲
- GitHub Issue #68・親Issue #65・依存Issue #67、PR #78、詳細設計コメント #6308861040
- `docs/issue_68/詳細設計.md`、`docs/issue_67/詳細設計.md`、`docs/要件定義書.md`
- `app/models/{transaction,image_import_draft,import_source,import_entry,import_event,import_guard,account,category,payment_method,setting}.rb`、関連concern、`db/schema.rb`
- `app/services/imports/*`、`ImageImportDraftBuilder`、`Gemini::TransactionExtractor`
- 取込・取引・設定・マスタのcontroller、候補詳細view、関連model/service/request spec、並行テストヘルパー
- テスト未実行（文書フェーズとして未実行との提示あり）

## 指摘
### [MAJOR]-1 予定を実績化するlink経路の整合性検証が不足している
- 箇所: 詳細設計4.4、5.4、テスト方針T5
- 根拠: 4.4の検証対象は「approve/distinct/adopt_revision/auto_apply」と訂正に限定され、5.4も検証追加先を`Applier#create_transaction`としている。一方、`app/services/imports/applier.rb:108`の`link`は別経路であり、114行目で予定を実績へ変更する。`app/models/transaction.rb:24`以降の既存validationはカテゴリ区分・支払経路の整合性を検証しない。予定実績化は`spec/services/imports/applier_spec.rb:45`でも既存機能として確認できる。
- 問題: 通常候補からlinkする場合、支出に収入カテゴリを持つ予定や、現金支払方法に銀行口座を持つ予定を実績化できる。特殊取引の昇格禁止や候補draftの検証だけでは、値を維持して昇格する対象Transactionの矛盾を防げない。
- 修正方針: `link`でplannedをactualに変更する直前に、対象Transactionの保存後の値へ共通整合性検証を適用する設計を追加する。不整合時は予定・候補・イベントを変更せず保留し、対象予定の修正へ案内する。正常な予定の実績化と、カテゴリ・支払経路が不整合な予定の拒否をテストへ追加する。

RESULT: FAIL
