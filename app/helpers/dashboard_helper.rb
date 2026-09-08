module DashboardHelper
  include SvgLineChartHelper

  LINE_CHART_HEIGHT = 200
  LINE_CHART_PADDING_TOP = 24 # 凡例(収入実績/支出実績)の表示分、他のグラフより上の余白を広めに取る
  LINE_CHART_PADDING_BOTTOM = 32
  LINE_Y_AXIS_WIDTH = 52
  LINE_Y_TICK_STEP = 100_000
  LINE_Y_MIN_SPAN = 200_000

  BAR_CHART_HEIGHT = 220
  BAR_CHART_PADDING_TOP = 16
  BAR_CHART_PADDING_BOTTOM = 90
  BAR_Y_AXIS_WIDTH = 44
  BAR_Y_TICK_STEP = 10_000
  BAR_Y_MIN_SPAN = 20_000
  # 1本の棒が占める幅の割合(残りは前後の棒との間隔になる)
  BAR_FILL_RATIO = 0.6
  # 回転させたカテゴリ名ラベルが重なり合わずに読める最低限の幅(px)。
  # カテゴリ数が多く、これを下回る場合は横スクロールさせる(#fluid_svg_style参照)。
  BAR_MIN_SLOT_WIDTH = 56

  # app/assets/stylesheets/application.css のCSSカスタムプロパティを直接参照することで、
  # ダークモード切り替え時にもグラフの配色が自動的に追従する。
  INCOME_COLOR = "var(--color-series-income)"
  EXPENSE_COLOR = "var(--color-series-expense)"
  BAR_COLOR = "var(--color-accent-1)"

  # 月別の収入実績/支出実績の推移を折れ線グラフ(インラインSVG)で描画する。
  # monthly_summaries は1〜12月順(MonthlySummary.build_for_year の戻り値)で渡すこと。
  # 資産推移グラフと同様、y軸を固定幅(px)で左端に表示し、グラフ本体はコンテナの
  # 幅いっぱいに追従させる。
  def monthly_trend_svg(monthly_summaries)
    incomes = monthly_summaries.map(&:income_actual)
    expenses = monthly_summaries.map(&:expense_actual)
    return content_tag(:p, "取引データを登録するとグラフが表示されます。") if (incomes + expenses).all?(&:zero?)

    min_value, max_value = nice_axis_domain(0, (incomes + expenses).max, step: LINE_Y_TICK_STEP, min_span: LINE_Y_MIN_SPAN, anchor_zero: true)
    ticks = y_axis_ticks(min_value: min_value, max_value: max_value, step: LINE_Y_TICK_STEP,
                          height: LINE_CHART_HEIGHT, padding_top: LINE_CHART_PADDING_TOP, padding_bottom: LINE_CHART_PADDING_BOTTOM)

    income_points, expense_points = fluid_line_points(
      [incomes, expenses], height: LINE_CHART_HEIGHT,
      padding_top: LINE_CHART_PADDING_TOP, padding_bottom: LINE_CHART_PADDING_BOTTOM,
      min_value: min_value, max_value: max_value
    )

    body_axes = svg_chart_body_axes(height: LINE_CHART_HEIGHT, padding_bottom: LINE_CHART_PADDING_BOTTOM,
                                     ticks: ticks, x_labels: thin_labels(monthly_summaries.map { |s| "#{s.month}月" }))
    income_series = fluid_line_series(income_points, INCOME_COLOR) { |i| tag.title("#{monthly_summaries[i].month}月: #{number_to_currency(incomes[i], unit: '¥', precision: 0)}") }
    expense_series = fluid_line_series(expense_points, EXPENSE_COLOR) { |i| tag.title("#{monthly_summaries[i].month}月: #{number_to_currency(expenses[i], unit: '¥', precision: 0)}") }
    legend = tag.text("収入実績", x: 4, y: 14, style: "fill: #{INCOME_COLOR}", "font-size": 12, "font-weight": 600) +
             tag.text("支出実績", x: 74, y: 14, style: "fill: #{EXPENSE_COLOR}", "font-size": 12, "font-weight": 600)

    body_svg = content_tag(:svg, legend + body_axes + income_series + expense_series, height: LINE_CHART_HEIGHT, style: FLUID_SVG_STYLE)
    y_axis_svg = svg_y_axis(width: LINE_Y_AXIS_WIDTH, height: LINE_CHART_HEIGHT, ticks: ticks,
                             value_formatter: ->(v) { v.zero? ? "0" : "#{(v / 10_000).round}万" })

    content_tag(:div, class: "chart-with-fixed-axis") do
      y_axis_svg + content_tag(:div, body_svg, class: "chart-body")
    end
  end

  # カテゴリ別の当月支出を棒グラフ(インラインSVG)で描画する。
  # 折れ線グラフと同様、y軸を固定幅(px)で左端に表示し、グラフ本体はコンテナの
  # 幅いっぱいに追従させる(棒の幅・間隔もコンテナ幅に対する%で計算する)。
  # ただしカテゴリ数が多くBAR_MIN_SLOT_WIDTHを下回る場合は、棒とラベルが
  # 潰れて読めなくなるのを避けるため横スクロールさせる(#fluid_svg_style参照)。
  def category_expense_bar_svg(category_expenses)
    return content_tag(:p, "今月は表示できる支出カテゴリがありません。") if category_expenses.empty?

    spents = category_expenses.map(&:spent)
    min_value, max_value = nice_axis_domain(0, spents.max, step: BAR_Y_TICK_STEP, min_span: BAR_Y_MIN_SPAN, anchor_zero: true)
    range = (max_value - min_value).nonzero? || 1
    ticks = y_axis_ticks(min_value: min_value, max_value: max_value, step: BAR_Y_TICK_STEP,
                          height: BAR_CHART_HEIGHT, padding_top: BAR_CHART_PADDING_TOP, padding_bottom: BAR_CHART_PADDING_BOTTOM)

    usable_height = BAR_CHART_HEIGHT - BAR_CHART_PADDING_TOP - BAR_CHART_PADDING_BOTTOM
    axis_bottom = BAR_CHART_PADDING_TOP + usable_height

    gridlines = svg_gridlines(ticks: ticks)
    x_axis_line = tag.line(x1: "0%", y1: axis_bottom, x2: "100%", y2: axis_bottom, class: "chart-axis-line")

    count = category_expenses.size
    slot_percent = 100.0 / count
    bar_percent = slot_percent * BAR_FILL_RATIO
    gap_percent = (slot_percent - bar_percent) / 2

    bars = category_expenses.each_with_index.map do |entry, index|
      bar_height = (entry.spent - min_value).to_f / range * usable_height
      x_percent = (index * slot_percent + gap_percent).round(2)
      center_percent = (index * slot_percent + (slot_percent / 2)).round(2)
      y = axis_bottom - bar_height
      label_y = axis_bottom + 14

      bar = tag.rect(x: "#{x_percent}%", y: y, width: "#{bar_percent.round(2)}%", height: bar_height, rx: 4, style: "fill: #{BAR_COLOR}") do
        tag.title("#{entry.category.name}: #{number_to_currency(entry.spent, unit: '¥', precision: 0)}")
      end
      # transformのrotate()は%座標を扱えないため、CSSのtransform-originで回転の
      # 軸(ラベルの右下=text-anchor: endの基準点相当)を指定して回転させる。
      # transform-boxを指定しない場合、%はSVG全体(ビューポート)基準になってしまい
      # 全ラベルがグラフ右下の1点を中心に回転してしまうため、fill-boxで
      # 各ラベル自身の描画範囲を基準にする。
      label = tag.text(entry.category.name, x: "#{center_percent}%", y: label_y, class: "chart-axis-label", "text-anchor": "end",
                        style: "transform: rotate(-45deg); transform-origin: 100% 100%; transform-box: fill-box;")
      bar + label
    end.join.html_safe

    body_svg = content_tag(:svg, gridlines + x_axis_line + bars, height: BAR_CHART_HEIGHT,
                            style: fluid_svg_style(min_width_px: count * BAR_MIN_SLOT_WIDTH))
    y_axis_svg = svg_y_axis(width: BAR_Y_AXIS_WIDTH, height: BAR_CHART_HEIGHT, ticks: ticks,
                             value_formatter: ->(v) { v.zero? ? "0" : "#{(v / 10_000).round}万" })

    content_tag(:div, class: "chart-with-fixed-axis") do
      y_axis_svg + content_tag(:div, body_svg, class: "chart-body")
    end
  end
end
