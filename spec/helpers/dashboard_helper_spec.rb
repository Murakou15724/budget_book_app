require "rails_helper"

RSpec.describe DashboardHelper, type: :helper do
  describe "#category_expense_bar_svg" do
    def category_expense(name, spent: 1000)
      category = Category.create!(name: name, kind: :expense, position: 1)
      CategoryExpenseSummary.new(category: category, spent: spent, budget: 10_000)
    end

    it "カテゴリ数が少なければmin-widthは小さく、通常のコンテナ幅では横スクロールが発生しない" do
      expenses = 3.times.map { |i| category_expense("カテゴリ#{i}") }

      html = helper.category_expense_bar_svg(expenses)

      expect(html).to include("min-width: #{3 * DashboardHelper::BAR_MIN_SLOT_WIDTH}px;")
    end

    it "カテゴリ数が多い場合は、棒とラベルが潰れないようmin-widthを大きくして横スクロールできるようにする" do
      expenses = 20.times.map { |i| category_expense("カテゴリ#{i}") }

      html = helper.category_expense_bar_svg(expenses)

      expect(html).to include("min-width: #{20 * DashboardHelper::BAR_MIN_SLOT_WIDTH}px;")
    end
  end
end
