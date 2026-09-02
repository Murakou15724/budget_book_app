require "rails_helper"

RSpec.describe "shifting a transaction's credit card payment due date from the unpaid list", type: :request do
  before { Setting.current.update!(credit_card_closing_day: 31, credit_card_payment_day: 26) }

  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "クレカ", position: 1) }
  let!(:account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 1) }

  let!(:transaction) do
    Transaction.create!(
      date: Date.new(2028, 7, 25), entry_type: :actual, direction: :expense, amount: 1000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )
  end

  it "次月ボタンで支払予定日が1サイクル後ろにずれる" do
    original_due_on = transaction.credit_card_payment_due_on

    patch shift_credit_card_payment_due_on_transaction_path(transaction, direction: "next")

    expect(response).to redirect_to(credit_card_unpaids_path)
    expect(transaction.reload.credit_card_payment_due_on).to eq(original_due_on.advance(months: 1).beginning_of_month.then { |m| Transaction.resolve_payment_due_date(m) })
  end

  it "前月ボタンで支払予定日が1サイクル前にずれる" do
    original_due_on = transaction.credit_card_payment_due_on

    patch shift_credit_card_payment_due_on_transaction_path(transaction, direction: "prev")

    expect(transaction.reload.credit_card_payment_due_on).to eq(original_due_on.advance(months: -1).beginning_of_month.then { |m| Transaction.resolve_payment_due_date(m) })
  end

  it "クレカ未払い一覧に前月/次月ボタンが表示される" do
    get credit_card_unpaids_path

    expect(response.body).to include(shift_credit_card_payment_due_on_transaction_path(transaction, direction: "prev"))
    expect(response.body).to include(shift_credit_card_payment_due_on_transaction_path(transaction, direction: "next"))
  end
end
