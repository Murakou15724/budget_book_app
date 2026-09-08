require "rails_helper"

RSpec.describe "dashboard balance estimate", type: :request do
  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "現金", position: 1) }
  let!(:account) { Account.create!(name: "現金口座", position: 1) }

  it "収支見込みは収入見込み(budget_planの基本手取り月収)から支出実績を引いた額になる" do
    Setting.current.update!(monthly_income_estimate: 300_000)
    Transaction.create!(
      date: Date.current, entry_type: :actual, direction: :expense, category: category,
      amount: 180_000, payment_method: payment_method, account: account
    )

    get dashboard_path

    expect(response.body).to include("収入見込み")
    expect(response.body).to include("収支見込み")
    expect(response.body).to include("¥300,000")
    expect(response.body).to include("¥120,000")
    expect(response.body).not_to include(">収支<")
  end

  it "収入見込みが未設定(nil)の場合は0円扱いになる" do
    get dashboard_path

    expect(response).to have_http_status(:ok)
  end
end
