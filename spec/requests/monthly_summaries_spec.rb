require "rails_helper"

RSpec.describe "monthly summaries page", type: :request do
  it "renders the reordered columns with budget_remaining_rate" do
    category = Category.create!(name: "食費", kind: :expense, position: 1, monthly_budget: 30000)
    payment_method = PaymentMethod.create!(name: "現金", position: 1)
    account = Account.create!(name: "現金口座", position: 1)
    Transaction.create!(
      date: Date.new(2026, 4, 10), entry_type: :actual, direction: :expense, category: category,
      amount: 10000, payment_method: payment_method, account: account
    )

    get monthly_summaries_path(year: 2026)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("支出実績")
    expect(response.body).to include("残り予算%")
    expect(response.body).to include("66.7%")
  end
end
