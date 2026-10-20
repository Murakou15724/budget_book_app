## 確認範囲
- Issue #67 本文、詳細設計コメント 6262287659
- 関連Issue #65 / #68 / #69 / #70 / #71 / #76 / #77
- `/home/murakamiko/projects/AGENTS.md`、Reviewer共通ルール
- `app/models/{transaction,image_import_draft,account,category,payment_method,account_reconciliation}.rb`
- `app/models/concerns/credit_card_payment_cycle.rb`
- 画像取込・候補・取引・マスタの各Controller、画像候補一覧View、routes
- `app/services/image_import_draft_builder.rb`、`app/services/gemini/transaction_extractor.rb`
- `db/schema.rb`、既存rake・旧データ取込処理
- 既存Builder・画像取込・Transaction・残高整合性spec、`spec/rails_helper.rb`
- `docs/アプリケーション仕様書.md`
- 設計のみ・テスト未実行の提示を確認。レビュー中もテスト未実行

## 指摘

### [MAJOR]-1 候補の永久保持に伴うマスタ削除制限が設計されていない
- 箇所: 第3章の「処理後もdraftを削除せず」、第7章の変更対象・第10章のマスタ削除テスト
- 根拠: `db/schema.rb:246`〜248でdraftからAccount・Category・PaymentMethodへのFKが存在する。`app/models/category.rb:6`〜8、`app/models/payment_method.rb:2`〜3にはdraftへの削除制限がない。削除処理は`app/controllers/categories_controller.rb:34`、`app/controllers/payment_methods_controller.rb:32`で`destroy`の成否のみ扱う。設計に追加されるAccountの制限はImportSourceに対するものだけ。
- 問題: 承認・却下済みdraftが残るため、関連する取引やテンプレートを削除しても、使用していたカテゴリ・支払方法を削除するとFK違反になる。取込元口座と異なる反映口座も同様。既存の削除画面から正常に理由を表示できず、未処理例外となる。
- 修正方針: 履歴保持方針に合わせ、各マスタにdraft関連の`restrict_with_error`等を明記するか、履歴を維持した参照解除方法を設計する。対象ファイルと、処理済み候補のみが残る場合の削除request specを追加する。

### [MAJOR]-2 削除確認後の終端結果が再度conflictになる状態遷移になっている
- 箇所: 第5.1節の整合確認順序、第5.3節の`acknowledge_deleted`
- 根拠: 第5.1節は「既存targetが消失・変更済みならconflictを優先する」とする。一方、第5.3節は削除確認後に「rejectedへ遷移して歴史IDと削除前snapshotを維持する」とする。第3章のEntryには削除確認済みを区別する項目がなく、整合確認から除外する規則も記載されていない。
- 問題: 削除確認後もtargetは存在せず、歴史IDと旧snapshotが残るため、記載された整合確認を再実行すると再びconflictになる。同じ取込・候補の再処理で削除確認が繰り返される。
- 修正方針: 削除を確認済みの終端状態を識別できる情報と判定順序を定義する。例えば専用状態または確認済み削除情報を保持し、その結果は欠落検査より先に返す。確認後の再送・再承認・閲覧でもconflictへ戻らず、取引も再生成されないテストを追加する。

RESULT: FAIL
