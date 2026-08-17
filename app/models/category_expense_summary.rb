# カテゴリ別の当月支出と予算消費率。DBに保持せず取引データ等から都度計算する。
class CategoryExpenseSummary
  attr_reader :category, :spent, :budget

  def self.build_for_month(year, month)
    spent_by_category = Transaction.expense.actual.in_month(year, month).group(:category_id).sum(:amount)
    overrides = CategoryMonthlyBudget.where(year: year, month: month).index_by(&:category_id)

    Category.expense.order(:position, :name).map do |category|
      new(
        category: category,
        spent: spent_by_category[category.id] || 0,
        budget: overrides[category.id]&.budget || category.monthly_budget || 0
      )
    end
  end

  def initialize(category:, spent:, budget:)
    @category = category
    @spent = spent
    @budget = budget
  end

  def usage_rate
    return nil if budget.zero?

    spent.to_f / budget
  end
end
