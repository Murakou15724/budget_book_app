class CreditCardUnpaidsController < ApplicationController
  def index
    @transactions = Transaction.unpaid.includes(:category, :payment_method, :account).order(date: :asc, id: :asc)
    @grouped_transactions = @transactions.group_by { |t| t.payment_method.name }
    @total = @transactions.sum(&:amount)
  end
end
