require "rails_helper"

RSpec.describe "transactions index credit card display", type: :request do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "クレカ", position: 1) }
  let!(:account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 1) }

  it "支払予定日バッジを表示するが、支払済にするチェックボックスは表示しない(クレカ未払い一覧へのリンクに一本化)" do
    Transaction.create!(
      date: Date.new(2028, 7, 20), entry_type: :actual, direction: :expense, amount: 3000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )

    get transactions_path(range: "all")

    expect(response.body).to include("支払予定: 9/26")
    expect(response.body).not_to include("支払済にする")
    expect(response.body).to include(credit_card_unpaids_path)
  end
end
