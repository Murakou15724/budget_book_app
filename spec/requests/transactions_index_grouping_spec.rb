require "rails_helper"

RSpec.describe "transactions index unpaid grouping", type: :request do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "クレカ", position: 1) }
  let!(:account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 1) }

  it "クレカ支払状況=未払で絞り込むと支払予定日ごとにグルーピングして表示する" do
    Transaction.create!(
      date: Date.new(2028, 7, 20), entry_type: :actual, direction: :expense, amount: 3000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )
    Transaction.create!(
      date: Date.new(2028, 8, 20), entry_type: :actual, direction: :expense, amount: 5000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )

    get transactions_path(credit_card_status: "unpaid", range: "all")

    expect(response.body).to include("9月26日払い分")
    expect(response.body).to include("10月26日払い分")
  end

  it "未払以外で絞り込んだ場合は通常のフラット表示(個別支払予定バッジ付き)のまま" do
    Transaction.create!(
      date: Date.new(2028, 7, 20), entry_type: :actual, direction: :expense, amount: 3000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )

    get transactions_path(range: "all")

    expect(response.body).not_to include("払い分（")
    expect(response.body).to include("支払予定: 9/26")
  end

  it "支払済にする際に確認ダイアログ(turbo_confirm)が付く" do
    get transactions_path(range: "all")

    expect(response.body).to include("data-turbo-confirm=")
  end
end
