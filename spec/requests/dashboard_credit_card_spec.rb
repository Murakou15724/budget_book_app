require "rails_helper"

RSpec.describe "dashboard next credit card payment", type: :request do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "クレカ", position: 1) }
  let!(:account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 1) }

  it "shows the nearest upcoming credit card payment due date and total, plus the grand total when they differ" do
    Transaction.create!(
      date: Date.new(2028, 7, 20), entry_type: :actual, direction: :expense, amount: 3000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )
    Transaction.create!(
      date: Date.new(2028, 8, 20), entry_type: :actual, direction: :expense, amount: 5000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )

    get dashboard_path

    expect(response.body).to include("クレカ未払い(次回9/26)")
    expect(response.body).to include("¥3,000")
    expect(response.body).to include("未払い合計 ¥8,000")
  end

  it "does not show the grand-total line when there is only one upcoming payment group" do
    Transaction.create!(
      date: Date.new(2028, 7, 20), entry_type: :actual, direction: :expense, amount: 3000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )

    get dashboard_path

    expect(response.body).to include("クレカ未払い(次回9/26)")
    expect(response.body).not_to include("未払い合計")
  end

  it "shows a plain zero tile when there are no unpaid credit card transactions" do
    get dashboard_path

    expect(response.body).to include("クレカ未払い")
    expect(response.body).not_to include("クレカ未払い(次回")
  end
end
