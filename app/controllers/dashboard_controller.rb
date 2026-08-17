class DashboardController < ApplicationController
  def index
    @year = resolve_year(params[:year])
    # 「今月」は実際の現在年月に対してのみ意味を持つ。表示中の年が現在年と異なる場合、
    # 今月の集計・カテゴリ別支出は算出しない(過去/未来の年に今日の月日を当てはめない)。
    @current_month = Date.current.month if @year == Date.current.year

    @monthly_summaries = MonthlySummary.build_for_year(@year)
    @current_summary = @current_month && @monthly_summaries.find { |s| s.month == @current_month }

    @annual_income = @monthly_summaries.sum(&:income_actual)
    @annual_expense = @monthly_summaries.sum(&:expense_actual)

    @latest_snapshot = AssetSnapshot.order(recorded_on: :desc, id: :desc).first
    @total_assets = @latest_snapshot&.total_balance || 0
    @credit_card_unpaid_total = Transaction.unpaid.sum(:amount)

    setting = Setting.current
    @level_unit_amount = setting.level_unit_amount
    @savings_level = @total_assets / @level_unit_amount
    @total_savings_goal = setting.total_savings_goal || 0
    @goal_progress_rate = @total_savings_goal.zero? ? 0.0 : @total_assets.to_f / @total_savings_goal

    @category_expenses = @current_month ? CategoryExpenseSummary.build_for_month(@year, @current_month) : []
  end
end
