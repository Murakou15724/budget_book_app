require "rails_helper"

RSpec.describe "monthly summaries pending actual balance", type: :request do
  it "進行中の月は実績収支を「未確定」として隠し、既に終わった月は数値をそのまま表示する" do
    today = Date.current

    get monthly_summaries_path(year: today.year)

    expect(response.body).to include("未確定")
    expect(response.body).to include("actual_balance_#{today.year}_#{today.month}")
    if today.year > 2026 || (today.year == 2026 && today.month > 1)
      # 少なくとも1月は既に終わっているはずなので、通常表示のセルも存在する
      expect(response.body).to match(/<td>\s*¥[\d,-]+\s*<\/td>/)
    end
  end

  it "非同期エンドポイントはその月の実績収支を返す" do
    category = Category.create!(name: "食費", kind: :expense, position: 1)
    payment_method = PaymentMethod.create!(name: "現金", position: 1)
    account = Account.create!(name: "現金口座", position: 1)
    Transaction.create!(
      date: Date.new(2026, 3, 10), entry_type: :actual, direction: :income, category: category.tap { |c| c.update!(kind: :income) },
      amount: 200_000, payment_method: payment_method, account: account
    )
    Transaction.create!(
      date: Date.new(2026, 3, 15), entry_type: :actual, direction: :expense, category: Category.create!(name: "日用品", kind: :expense, position: 2),
      amount: 50_000, payment_method: payment_method, account: account
    )

    get monthly_summary_actual_balance_path(year: 2026, month: 3)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('turbo-frame id="actual_balance_2026_3"')
    expect(response.body).to include("¥150,000")
  end
end
