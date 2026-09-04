class AddCreditCardPaymentAccountToSettings < ActiveRecord::Migration[7.1]
  def change
    # クレカ引落元の口座(任意)。設定されている場合のみ、資産スナップショットの
    # 整合性チェックでクレカ支払済への変更を口座残高の減少要因として扱う。
    add_reference :settings, :credit_card_payment_account, foreign_key: { to_table: :accounts }, null: true
  end
end
