# 月別の収支・予算集計値。DBに保持せず、取引データ等から都度計算する(要件定義書6章)。
class MonthlySummary
  attr_reader :year, :month, :income_with_planned, :income_actual, :expense_actual,
              :monthly_budget, :monthly_savings_goal, :credit_card_expense, :investment_actual
  attr_accessor :cumulative_balance

  # 対象年の1〜12月分をまとめて計算する。年単位でTransaction/CategoryMonthlyBudgetを
  # 一括取得してからメモリ上で集計することでN+1を避ける。
  def self.build_for_year(year)
    savings_goal = Setting.current.monthly_savings_goal || 0
    expense_categories = Category.expense.to_a
    overrides_by_category = CategoryMonthlyBudget.where(year: year).group_by(&:category_id)

    transactions_by_month = Transaction
                             .where(date: Date.new(year, 1, 1)..Date.new(year, 12, -1))
                             .group_by { |t| t.date.month }

    cumulative = 0
    (1..12).map do |month|
      summary = for_month(
        year: year, month: month, month_transactions: transactions_by_month[month] || [],
        expense_categories: expense_categories, overrides_by_category: overrides_by_category, savings_goal: savings_goal
      )
      cumulative += summary.actual_balance
      summary.cumulative_balance = cumulative
      summary
    end
  end

  # 単月分のみ計算する(月次振り返りの編集画面など、年間の他の月の集計が不要な場面向け)。
  # cumulative_balanceは年間を通した計算が必要なため設定されない(nilのまま)。
  def self.build_for_month(year, month)
    for_month(
      year: year, month: month,
      month_transactions: Transaction.where(date: Date.new(year, month, 1)..Date.new(year, month, -1)),
      expense_categories: Category.expense.to_a,
      overrides_by_category: CategoryMonthlyBudget.where(year: year, month: month).group_by(&:category_id),
      savings_goal: Setting.current.monthly_savings_goal || 0
    )
  end

  def self.for_month(year:, month:, month_transactions:, expense_categories:, overrides_by_category:, savings_goal:)
    monthly_budget = expense_categories.sum do |category|
      override = overrides_by_category[category.id]&.find { |b| b.month == month }
      override&.budget || category.monthly_budget || 0
    end

    new(
      year: year,
      month: month,
      income_with_planned: month_transactions.select(&:income?).sum(&:amount),
      income_actual: month_transactions.select { |t| t.income? && t.actual? }.sum(&:amount),
      expense_actual: month_transactions.select { |t| t.expense? && t.actual? }.sum(&:amount),
      # クレカ利用額は「支払予定日」ではなく「利用日」で当月に属するかを判定する
      # (この月の予算消化・振り返りに使う値のため、支払日ベースにすると
      #  実際に使った月と表示上の月がズレてしまう)。
      credit_card_expense: month_transactions.select { |t| t.expense? && t.actual? && !t.not_applicable? }.sum(&:amount),
      # 投資(証券口座への入金等)は生活費の支出とは別枠で確認できるようにする
      # (支出合計には含めない。振替は資金の置き場所が変わるだけなので、
      #  投資と異なり金額を別枠表示する必要もなく、単に集計対象外とする)。
      investment_actual: month_transactions.select { |t| t.investment? && t.actual? }.sum(&:amount),
      monthly_budget: monthly_budget,
      monthly_savings_goal: savings_goal
    )
  end
  private_class_method :for_month

  def initialize(year:, month:, income_with_planned:, income_actual:, expense_actual:, monthly_budget:, monthly_savings_goal:, credit_card_expense:, investment_actual:)
    @year = year
    @month = month
    @income_with_planned = income_with_planned
    @income_actual = income_actual
    @expense_actual = expense_actual
    @monthly_budget = monthly_budget
    @monthly_savings_goal = monthly_savings_goal
    @credit_card_expense = credit_card_expense
    @investment_actual = investment_actual
  end

  def actual_balance
    income_actual - expense_actual
  end

  def budget_remaining
    monthly_budget - expense_actual
  end

  def budget_remaining_rate
    return 0.0 if monthly_budget.zero?

    budget_remaining.to_f / monthly_budget
  end

  def savings_achievement_rate
    return 0.0 if monthly_savings_goal.zero?

    actual_balance.to_f / monthly_savings_goal
  end
end
