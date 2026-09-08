require "rails_helper"

RSpec.describe "dashboard budget remaining rate", type: :request do
  let!(:payment_method) { PaymentMethod.create!(name: "現金", position: 1) }
  let!(:account) { Account.create!(name: "現金口座", position: 1) }

  def spend(amount, monthly_budget:)
    category = Category.create!(name: "食費#{amount}", kind: :expense, position: 1, monthly_budget: monthly_budget)
    Transaction.create!(
      date: Date.current, entry_type: :actual, direction: :expense, category: category,
      amount: amount, payment_method: payment_method, account: account
    )
  end

  it "通常時(25%超)は危険マークを表示しない" do
    spend(5000, monthly_budget: 10_000) # 残り50%

    get dashboard_path

    expect(response.body).to include("残り予算%")
    expect(response.body).to include("50.0%")
    expect(response.body).not_to include("⚠️")
  end

  it "残り25%以下(0%以上)は危険マークを表示するが赤字にはしない" do
    spend(8000, monthly_budget: 10_000) # 残り20%

    get dashboard_path

    expect(response.body).to match(/stat-tile__value\s*">\s*⚠️ 20\.0%/)
  end

  it "0%を下回ったら危険マークに加えて赤字(is-negative)で表示する" do
    spend(12_000, monthly_budget: 10_000) # 残り-20%

    get dashboard_path

    expect(response.body).to include("⚠️ ")
    expect(response.body).to match(/stat-tile__value is-negative">\s*⚠️ -20\.0%/)
  end

  it "月予算が未設定(0円)の場合は危険マークを出さない" do
    spend(5000, monthly_budget: 0)

    get dashboard_path

    expect(response.body).not_to include("⚠️")
  end
end
