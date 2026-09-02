class AddCreditCardPaymentDueOnOverrideToTransactionsAndDrafts < ActiveRecord::Migration[7.1]
  def change
    add_column :transactions, :credit_card_payment_due_on_override, :date
    add_column :image_import_drafts, :credit_card_payment_due_on_override, :date
  end
end
