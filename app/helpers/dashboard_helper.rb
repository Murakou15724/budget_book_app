module DashboardHelper
  include SvgLineChartHelper

  LINE_CHART_WIDTH = 640
  LINE_CHART_HEIGHT = 200
  BAR_WIDTH = 32
  BAR_GAP = 12
  BAR_CHART_HEIGHT = 220
  BAR_CHART_PADDING_TOP = 16
  BAR_CHART_PADDING_BOTTOM = 90
  BAR_CHART_PADDING_LEFT = 24

  # 月別の収入実績/支出実績の推移を折れ線グラフ(インラインSVG)で描画する。
  # monthly_summaries は1〜12月順(MonthlySummary.build_for_year の戻り値)で渡すこと。
  def monthly_trend_svg(monthly_summaries)
    incomes = monthly_summaries.map(&:income_actual)
    expenses = monthly_summaries.map(&:expense_actual)
    points_list = scaled_line_chart_points([incomes, expenses], width: LINE_CHART_WIDTH, height: LINE_CHART_HEIGHT)
    return content_tag(:p, "取引データを登録するとグラフが表示されます。") if points_list.nil?

    income_points, expense_points = points_list
    income_series = svg_line_series(income_points, "#2f6f4e") { |i| tag.title("#{monthly_summaries[i].month}月: #{number_to_currency(incomes[i], unit: '¥', precision: 0)}") }
    expense_series = svg_line_series(expense_points, "#a4373a") { |i| tag.title("#{monthly_summaries[i].month}月: #{number_to_currency(expenses[i], unit: '¥', precision: 0)}") }

    legend = tag.text("収入実績", x: DEFAULT_PADDING, y: 14, fill: "#2f6f4e", "font-size": 12) +
             tag.text("支出実績", x: DEFAULT_PADDING + 80, y: 14, fill: "#a4373a", "font-size": 12)

    content_tag(:svg, width: LINE_CHART_WIDTH, height: LINE_CHART_HEIGHT, viewBox: "0 0 #{LINE_CHART_WIDTH} #{LINE_CHART_HEIGHT}") do
      legend + income_series + expense_series
    end
  end

  # カテゴリ別の当月支出を棒グラフ(インラインSVG)で描画する。
  def category_expense_bar_svg(category_expenses)
    return content_tag(:p, "支出カテゴリが登録されていません。") if category_expenses.empty?

    max_spent = category_expenses.map(&:spent).max
    chart_width = BAR_CHART_PADDING_LEFT + (category_expenses.size * (BAR_WIDTH + BAR_GAP))
    usable_height = BAR_CHART_HEIGHT - BAR_CHART_PADDING_TOP - BAR_CHART_PADDING_BOTTOM

    bars = category_expenses.each_with_index.map do |entry, index|
      bar_height = max_spent.zero? ? 0 : (entry.spent.to_f / max_spent * usable_height)
      x = BAR_CHART_PADDING_LEFT + (index * (BAR_WIDTH + BAR_GAP))
      y = BAR_CHART_PADDING_TOP + usable_height - bar_height
      label_y = BAR_CHART_PADDING_TOP + usable_height + 14

      bar = tag.rect(x: x, y: y, width: BAR_WIDTH, height: bar_height, fill: "#2f3e46") do
        tag.title("#{entry.category.name}: #{number_to_currency(entry.spent, unit: '¥', precision: 0)}")
      end
      label = tag.text(entry.category.name, x: x + (BAR_WIDTH / 2), y: label_y, "font-size": 11,
                        "text-anchor": "end", transform: "rotate(-45 #{x + (BAR_WIDTH / 2)} #{label_y})")
      bar + label
    end.join.html_safe

    content_tag(:svg, width: chart_width, height: BAR_CHART_HEIGHT, viewBox: "0 0 #{chart_width} #{BAR_CHART_HEIGHT}") do
      bars
    end
  end
end
