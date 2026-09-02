class CreditCardUnpaidsController < ApplicationController
  def index
    @grouped_transactions = Transaction.unpaid_grouped_by_payment_due_date
    @total = @grouped_transactions.values.sum { |transactions| transactions.sum(&:amount) }
  end
end
