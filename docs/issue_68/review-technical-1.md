## 確認範囲
- GitHub Issue #68・#65本文、PR #78、詳細設計コメント 6308861040
- `docs/issue_68/詳細設計.md`、`docs/issue_67/詳細設計.md`、`docs/要件定義書.md`
- `db/schema.rb`、既存取込追跡migration
- `ImageImportDraft`、`Transaction`、`Account`、`ImportSource`、`ImportEntry`、`ImportEvent`、`ImportGuard`
- Builder、Extractor、EntryRecorder、ImageReceiver、Matcher、Applier、ReviewToken、TargetIntegrity
- 取込関連Controller、`AccountsController`
- Applier・Transaction・クレカ整合性の既存spec、並行検証用ヘルパー
- アプリテスト未実行の提示を確認。レビュー中のテスト実行なし

## 指摘

### [MAJOR]-1 未知directionをnilで保存する仕様が既存NOT NULL制約と衝突する
- 箇所: 詳細設計5.2「未知directionはnil」、6章migration、7章
- 根拠: `db/schema.rb:90` の `image_import_drafts.direction` は `default: 1, null: false`。設計4.5・5.2は不完全な抽出行を候補として保存する一方、この制約の変更を定義していない。
- 問題: direction不明の行を保存するとNOT NULL違反になり、文書単位のtransactionがrollbackする。不明な1行を手動確認へ残せず、同じ画像の正常行も保存できない。
- 修正方針: 未確定directionの永続化方法を明記する。nilを採用するなら既存値を維持してNULLを許可し、支出への暗黙補完を防ぐdefaultの扱いも定義する。正常行とdirection不明行が混在しても全候補を保存できるmigration／Builder検証を追加する。

### [MAJOR]-2 元候補のない手動ルール作成ではnonceの保存先が存在しない
- 箇所: 詳細設計4.1、5.1、7章の冪等化
- 根拠: 4.1は `confirmation_entry_id` を「手動新規はNULL」とし、5.1はcreateのnonceを「元候補eventに記録」する設計。`app/models/import_event.rb:2` と `db/schema.rb:156` はImportDocumentを必須としている。
- 問題: 手動新規ルールには元候補・文書がないため、定義したnonce保存方式を利用できない。Guardだけでは同じ送信の逐次再実行を判別できず、重複ルールが作成される。4.2の仕様では、その後の一致候補がすべて多重一致で保留になる。
- 修正方針: 候補由来・手動新規の両方に使える永続的な作成nonceと結果参照先を定義し、ルール作成と同一transactionで保存する。手動新規フォームの二重送信・並行送信・応答喪失後の再送も、同じルールを返すテスト対象にする。

### [MAJOR]-3 追加する移動先口座FKに対応した削除制限が不足する
- 箇所: 詳細設計6章Account変更、7章 `image_import_drafts.to_account_id`
- 根拠: `app/models/account.rb:12` のdraft関連は `account_id` 側のみ。既存の移動先参照はTransaction・QuickEntryTemplate用に別関連を定義している（同15–20行）。`app/controllers/accounts_controller.rb:32` はdestroyのfalseを扱うが、FK違反例外は処理しない。設計はdraftの移動先FKを追加する一方、その逆関連・削除制限を指定していない。
- 問題: 未反映・却下済み候補の移動先としてだけ使用している口座を削除すると、既存のrestrict判定を通過してDBのFK違反になり、理由付きの削除拒否ではなく500になる。
- 修正方針: Accountにdraftの `to_account_id` を参照する逆関連と `dependent: :restrict_with_error` を追加する設計を明記する。移動先としてだけ使われる未処理・処理済み候補について、削除が理由付きで拒否され候補・口座が残るrequest specを追加する。

RESULT: FAIL
