require "rails_helper"

RSpec.describe "budget plan base budget editing", type: :request do
  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1, monthly_budget: 30000) }

  it "updates the base monthly budget via the categories param" do
    patch budget_plan_path, params: { year: 2026, categories: { category.id.to_s => "40000" }, budgets: {} }
    expect(response).to redirect_to(edit_budget_plan_path(year: 2026))
    expect(category.reload.monthly_budget).to eq(40000)
  end

  it "does not create spurious per-month overrides for untouched fields when the base changes in the same submit" do
    # シミュレーション: 画面上、全月の入力欄には旧基本月予算(30000)がプリフィルされたまま送信される
    stale_prefill = "30000"
    budgets_params = (1..12).index_with { stale_prefill }.transform_keys { |m| "#{category.id}-#{m}" }

    patch budget_plan_path, params: { year: 2026, categories: { category.id.to_s => "40000" }, budgets: budgets_params }

    expect(category.reload.monthly_budget).to eq(40000)
    expect(CategoryMonthlyBudget.where(category_id: category.id, year: 2026).count).to eq(0)
  end

  it "still creates a real override when a month value differs from the original base" do
    patch budget_plan_path, params: { year: 2026, categories: {}, budgets: { "#{category.id}-4" => "50000" } }

    override = CategoryMonthlyBudget.find_by(category_id: category.id, year: 2026, month: 4)
    expect(override.budget).to eq(50000)
  end

  describe "収入見込み" do
    it "基本手取り月収を更新できる" do
      patch budget_plan_path, params: { year: 2026, categories: {}, budgets: {}, income_estimate_base: "300000" }

      expect(Setting.current.reload.monthly_income_estimate).to eq(300_000)
    end

    it "基本値と異なる月別の値だけ上書きとして保存する" do
      Setting.current.update!(monthly_income_estimate: 300_000)

      patch budget_plan_path, params: {
        year: 2026, categories: {}, budgets: {}, income_estimate_base: "300000",
        income_estimate_budgets: { "12" => "500000" }
      }

      override = IncomeMonthlyEstimate.find_by(year: 2026, month: 12)
      expect(override.amount).to eq(500_000)
    end

    it "基本値と同額の月は上書きを作らない(既存の上書きがあれば解除する)" do
      Setting.current.update!(monthly_income_estimate: 300_000)
      IncomeMonthlyEstimate.create!(year: 2026, month: 6, amount: 400_000)

      patch budget_plan_path, params: {
        year: 2026, categories: {}, budgets: {}, income_estimate_base: "300000",
        income_estimate_budgets: { "6" => "300000" }
      }

      expect(IncomeMonthlyEstimate.find_by(year: 2026, month: 6)).to be_nil
    end
  end
end
