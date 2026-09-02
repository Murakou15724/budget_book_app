require "rails_helper"

RSpec.describe "transaction form payment due date field", type: :request do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "クレカ", position: 1) }
  let!(:account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 1) }

  it "未払のクレカ取引を編集する画面に支払予定日の編集フィールドが出る" do
    transaction = Transaction.create!(
      date: Date.new(2028, 8, 20), entry_type: :actual, direction: :expense, amount: 1000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )

    get edit_transaction_path(transaction)

    expect(response.body).to include("name=\"transaction[credit_card_payment_due_on_override]\"")
    expect(response.body).to include('value="2028-10-26"')
  end

  it "現金取引の編集画面にはフィールドが出ない" do
    cash_method = PaymentMethod.create!(name: "現金2", position: 2)
    cash_account = Account.create!(name: "現金2", kind: :cash, position: 2)
    transaction = Transaction.create!(
      date: Date.new(2028, 8, 20), entry_type: :actual, direction: :expense, amount: 1000,
      category: category, payment_method: cash_method, account: cash_account, credit_card_status: :not_applicable
    )

    get edit_transaction_path(transaction)

    expect(response.body).not_to include("credit_card_payment_due_on_override")
  end
end
