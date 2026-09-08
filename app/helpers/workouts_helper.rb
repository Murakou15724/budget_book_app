module WorkoutsHelper
  include SvgLineChartHelper

  CHART_HEIGHT = 140
  CHART_PADDING_TOP = 16
  CHART_PADDING_BOTTOM = 28
  Y_AXIS_WIDTH = 40
  Y_TICK_STEP = 50
  Y_MIN_SPAN = 100
  LINE_COLOR = "var(--color-accent-1)"

  # 直近14日のXP推移をインラインSVGの折れ線グラフで描画する。
  # dates_with_days: 日付の昇順配列。workout_days_by_date: date => WorkoutDay のハッシュ(記録がない日は未登録)。
  def xp_trend_svg(dates, workout_days_by_date)
    xps = dates.map { |date| workout_days_by_date[date]&.xp || 0 }

    min_value, max_value = nice_axis_domain(0, xps.max, step: Y_TICK_STEP, min_span: Y_MIN_SPAN, anchor_zero: true)
    ticks = y_axis_ticks(min_value: min_value, max_value: max_value, step: Y_TICK_STEP,
                          height: CHART_HEIGHT, padding_top: CHART_PADDING_TOP, padding_bottom: CHART_PADDING_BOTTOM)

    points = fluid_line_points([xps], height: CHART_HEIGHT, padding_top: CHART_PADDING_TOP, padding_bottom: CHART_PADDING_BOTTOM,
                                min_value: min_value, max_value: max_value)&.first

    return content_tag(:p, "まだ記録がありません。") if points.nil?

    body_axes = svg_chart_body_axes(height: CHART_HEIGHT, padding_bottom: CHART_PADDING_BOTTOM,
                                     ticks: ticks, x_labels: thin_labels(dates.map { |d| d.strftime("%-m/%-d") }))
    series = fluid_line_series(points, LINE_COLOR) do |index|
      tag.title("#{dates[index].strftime('%-m/%-d')}: #{xps[index]}XP")
    end
    body_svg = content_tag(:svg, body_axes + series, height: CHART_HEIGHT, style: fluid_svg_style)

    y_axis_svg = svg_y_axis(width: Y_AXIS_WIDTH, height: CHART_HEIGHT, ticks: ticks, value_formatter: ->(v) { v.to_i.to_s })

    content_tag(:div, class: "chart-with-fixed-axis") do
      y_axis_svg + content_tag(:div, body_svg, class: "chart-body")
    end
  end
end
