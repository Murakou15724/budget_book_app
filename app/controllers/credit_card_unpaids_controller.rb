class CreditCardUnpaidsController < ApplicationController
  def index
    @grouped_transactions = Transaction.unpaid_grouped_by_payment_due_date
    @total = @grouped_transactions.values.sum { |transactions| transactions.sum(&:amount) }
    @payment_accounts = Account.bank.order(:position, :name)
    @default_payment_account_id = Setting.current.credit_card_payment_account_id
  end
end
