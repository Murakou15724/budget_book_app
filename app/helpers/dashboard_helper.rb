module DashboardHelper
  include SvgLineChartHelper

  LINE_CHART_HEIGHT = 200
  LINE_CHART_PADDING_TOP = 24 # 凡例(収入実績/支出実績)の表示分、他のグラフより上の余白を広めに取る
  LINE_CHART_PADDING_RIGHT = 16
  LINE_CHART_PADDING_LEFT = 16
  LINE_CHART_PADDING_BOTTOM = 32
  # 資産推移グラフと同様、y軸ラベルを短い「万円」表記にすることでy軸の固定幅を抑え、
  # 12ヶ月分の点がスマホの画面幅に横スクロールなしで収まりやすくしている。
  LINE_Y_AXIS_WIDTH = 52
  LINE_BODY_MIN_WIDTH = 200
  LINE_POINT_SPACING = 20
  LINE_Y_TICK_STEP = 100_000
  LINE_Y_MIN_SPAN = 200_000

  BAR_WIDTH = 20
  BAR_GAP = 8
  BAR_CHART_HEIGHT = 220
  BAR_CHART_PADDING_TOP = 16
  BAR_CHART_PADDING_BOTTOM = 90
  BAR_CHART_PADDING_LEFT = 16
  BAR_Y_AXIS_WIDTH = 44
  BAR_Y_TICK_STEP = 10_000
  BAR_Y_MIN_SPAN = 20_000

  # app/assets/stylesheets/application.css のCSSカスタムプロパティを直接参照することで、
  # ダークモード切り替え時にもグラフの配色が自動的に追従する。
  INCOME_COLOR = "var(--color-series-income)"
  EXPENSE_COLOR = "var(--color-series-expense)"
  BAR_COLOR = "var(--color-accent-1)"

  # 月別の収入実績/支出実績の推移を折れ線グラフ(インラインSVG)で描画する。
  # monthly_summaries は1〜12月順(MonthlySummary.build_for_year の戻り値)で渡すこと。
  # 資産推移グラフと同様、y軸を左端に固定表示し、グラフ本体だけを横スクロールさせる。
  def monthly_trend_svg(monthly_summaries)
    incomes = monthly_summaries.map(&:income_actual)
    expenses = monthly_summaries.map(&:expense_actual)
    return content_tag(:p, "取引データを登録するとグラフが表示されます。") if (incomes + expenses).all?(&:zero?)

    min_value, max_value = nice_axis_domain(0, (incomes + expenses).max, step: LINE_Y_TICK_STEP, min_span: LINE_Y_MIN_SPAN, anchor_zero: true)
    ticks = y_axis_ticks(min_value: min_value, max_value: max_value, step: LINE_Y_TICK_STEP,
                          height: LINE_CHART_HEIGHT, padding_top: LINE_CHART_PADDING_TOP, padding_bottom: LINE_CHART_PADDING_BOTTOM)

    body_width = [LINE_BODY_MIN_WIDTH, LINE_CHART_PADDING_LEFT + LINE_CHART_PADDING_RIGHT + ((monthly_summaries.size - 1) * LINE_POINT_SPACING)].max
    points_list = scaled_line_chart_points(
      [incomes, expenses], width: body_width, height: LINE_CHART_HEIGHT,
      padding_left: LINE_CHART_PADDING_LEFT, padding_right: LINE_CHART_PADDING_RIGHT,
      padding_top: LINE_CHART_PADDING_TOP, padding_bottom: LINE_CHART_PADDING_BOTTOM,
      min_value: min_value, max_value: max_value
    )
    income_points, expense_points = points_list

    body_axes = svg_chart_body_axes(
      width: body_width, height: LINE_CHART_HEIGHT,
      padding_left: LINE_CHART_PADDING_LEFT, padding_right: LINE_CHART_PADDING_RIGHT, padding_bottom: LINE_CHART_PADDING_BOTTOM,
      ticks: ticks, x_labels: thin_labels(monthly_summaries.map { |s| "#{s.month}月" })
    )
    income_series = svg_line_series(income_points, INCOME_COLOR) { |i| tag.title("#{monthly_summaries[i].month}月: #{number_to_currency(incomes[i], unit: '¥', precision: 0)}") }
    expense_series = svg_line_series(expense_points, EXPENSE_COLOR) { |i| tag.title("#{monthly_summaries[i].month}月: #{number_to_currency(expenses[i], unit: '¥', precision: 0)}") }
    legend = tag.text("収入実績", x: LINE_CHART_PADDING_LEFT, y: 14, style: "fill: #{INCOME_COLOR}", "font-size": 12, "font-weight": 600) +
             tag.text("支出実績", x: LINE_CHART_PADDING_LEFT + 70, y: 14, style: "fill: #{EXPENSE_COLOR}", "font-size": 12, "font-weight": 600)

    body_svg = content_tag(:svg, legend + body_axes + income_series + expense_series,
                            width: body_width, height: LINE_CHART_HEIGHT, viewBox: "0 0 #{body_width} #{LINE_CHART_HEIGHT}")
    y_axis_svg = svg_y_axis(width: LINE_Y_AXIS_WIDTH, height: LINE_CHART_HEIGHT, ticks: ticks,
                             value_formatter: ->(v) { v.zero? ? "0" : "#{(v / 10_000).round}万" })

    content_tag(:div, class: "chart-with-fixed-axis") do
      y_axis_svg + content_tag(:div, body_svg, class: "card-scroll")
    end
  end

  # カテゴリ別の当月支出を棒グラフ(インラインSVG)で描画する。
  # 折れ線グラフと同様、y軸を左端に固定表示し、グラフ本体だけを横スクロールさせる。
  def category_expense_bar_svg(category_expenses)
    return content_tag(:p, "今月は表示できる支出カテゴリがありません。") if category_expenses.empty?

    spents = category_expenses.map(&:spent)
    min_value, max_value = nice_axis_domain(0, spents.max, step: BAR_Y_TICK_STEP, min_span: BAR_Y_MIN_SPAN, anchor_zero: true)
    range = (max_value - min_value).nonzero? || 1
    ticks = y_axis_ticks(min_value: min_value, max_value: max_value, step: BAR_Y_TICK_STEP,
                          height: BAR_CHART_HEIGHT, padding_top: BAR_CHART_PADDING_TOP, padding_bottom: BAR_CHART_PADDING_BOTTOM)

    chart_width = BAR_CHART_PADDING_LEFT + (category_expenses.size * (BAR_WIDTH + BAR_GAP))
    usable_height = BAR_CHART_HEIGHT - BAR_CHART_PADDING_TOP - BAR_CHART_PADDING_BOTTOM
    axis_bottom = BAR_CHART_PADDING_TOP + usable_height

    gridlines = svg_gridlines(padding_left: BAR_CHART_PADDING_LEFT, axis_right: chart_width, ticks: ticks)
    x_axis_line = tag.line(x1: BAR_CHART_PADDING_LEFT, y1: axis_bottom, x2: chart_width, y2: axis_bottom, class: "chart-axis-line")

    bars = category_expenses.each_with_index.map do |entry, index|
      bar_height = (entry.spent - min_value).to_f / range * usable_height
      x = BAR_CHART_PADDING_LEFT + (index * (BAR_WIDTH + BAR_GAP))
      y = axis_bottom - bar_height
      label_y = axis_bottom + 14

      bar = tag.rect(x: x, y: y, width: BAR_WIDTH, height: bar_height, rx: 4, style: "fill: #{BAR_COLOR}") do
        tag.title("#{entry.category.name}: #{number_to_currency(entry.spent, unit: '¥', precision: 0)}")
      end
      label = tag.text(entry.category.name, x: x + (BAR_WIDTH / 2), y: label_y, class: "chart-axis-label",
                        "text-anchor": "end", transform: "rotate(-45 #{x + (BAR_WIDTH / 2)} #{label_y})")
      bar + label
    end.join.html_safe

    body_svg = content_tag(:svg, gridlines + x_axis_line + bars, width: chart_width, height: BAR_CHART_HEIGHT, viewBox: "0 0 #{chart_width} #{BAR_CHART_HEIGHT}")
    y_axis_svg = svg_y_axis(width: BAR_Y_AXIS_WIDTH, height: BAR_CHART_HEIGHT, ticks: ticks,
                             value_formatter: ->(v) { v.zero? ? "0" : "#{(v / 10_000).round}万" })

    content_tag(:div, class: "chart-with-fixed-axis") do
      y_axis_svg + content_tag(:div, body_svg, class: "card-scroll")
    end
  end
end
