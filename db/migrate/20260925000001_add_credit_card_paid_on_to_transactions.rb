class AddCreditCardPaidOnToTransactions < ActiveRecord::Migration[7.1]
  def change
    # クレカの引落日。資産スナップショットの整合性チェックで、引落による残高減少をどの期間に計上するかの判定に使う。
    add_column :transactions, :credit_card_paid_on, :date
    add_index :transactions, :credit_card_paid_on

    # 既存の支払済取引も、支払予定日に引き落とされたものとみなす。
    up_only do
      Transaction.reset_column_information
      Transaction.where(credit_card_status: 2).find_each do |transaction|
        transaction.update_columns(credit_card_paid_on: transaction.credit_card_payment_due_on)
      end
    end
  end
end
