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
end
