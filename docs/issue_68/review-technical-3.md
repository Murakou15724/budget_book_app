## 確認範囲
- Issue #68・親Issue #65・依存Issue #67本文、PR #78
- 詳細設計コメント 6308861040、docs/issue_68/詳細設計.md
- docs/issue_67/詳細設計.md、docs/要件定義書.md
- 取込関連モデル・Controller、Imports各サービス、Builder・Extractor
- Transaction、CreditCardPaymentCycle、TargetIntegrity、DBスキーマ
- 既存取込spec・並行検証ヘルパー、spec/models/transaction_spec.rb
- Rails 7.1.6のActiveModel::Dirty#initialize_dup実装
- 提示された検証結果（git diff --check成功、文書フェーズにつきアプリテスト未実行）

## 指摘
### [MAJOR]-1 訂正プレビューのdupでは変更判定が保存時と異なる
- 箇所: 詳細設計5.7「Transactionのdupへ編集値を代入しvalidationとcallbackで正規化後のsnapshotを生成する」
- 根拠: `docs/issue_68/詳細設計.md:196`。`app/models/transaction.rb:76`は`credit_card_paid_on`自体が変更扱いなら再計算せず終了する。一方、Rails 7.1.6の`activemodel/lib/active_model/dirty.rb:248`の`initialize_dup`は各属性をDB既定値からのユーザー入力として再構成する。既存specの`spec/models/transaction_spec.rb:81`では支払済取引の利用日変更に引落日が追従する。
- 問題: 引落日が設定済みのpaid実績をdupすると、その引落日自体が変更扱いになる。利用日やdue overrideを訂正しても、既存の正規化処理ではプレビューの引落日が旧値のままになるが、永続化対象では再計算される。共通メソッドへの切り出しだけでは変更判定の違いが残り、確認した差分と保存結果が一致しない。
- 修正方針: dup直後・編集値代入前に変更追跡の基準を現在値へ揃えるか、元snapshotと編集差分を明示入力にした純粋な正規化処理を定義する。T10に、引落日設定済みのpaid実績で利用日変更・override変更・memoのみ変更を行い、プレビューsnapshotと保存後snapshotが完全一致する検証を追加する。

RESULT: FAIL
