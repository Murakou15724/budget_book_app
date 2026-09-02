class AddCreditCardCycleToSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :settings, :credit_card_closing_day, :integer, default: 15, null: false
    add_column :settings, :credit_card_payment_day, :integer, default: 26, null: false
  end
end
