class CreditCardUnpaidsController < ApplicationController
  def index
    @transactions = Transaction.unpaid.includes(:category, :payment_method, :account).order(date: :asc, id: :asc)
    @grouped_transactions = @transactions.group_by(&:credit_card_payment_due_on).sort.to_h
    @total = @transactions.sum(&:amount)
  end
end
