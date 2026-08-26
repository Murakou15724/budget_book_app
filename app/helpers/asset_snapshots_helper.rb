module AssetSnapshotsHelper
  include SvgLineChartHelper

  CHART_HEIGHT = 160
  CHART_PADDING_TOP = 24
  CHART_PADDING_RIGHT = 24
  CHART_PADDING_BOTTOM = 32
  Y_AXIS_WIDTH = 88
  BODY_MIN_WIDTH = 560
  POINT_SPACING = 56
  Y_TICK_STEP = 250_000
  Y_MIN_SPAN = 500_000

  # CSSカスタムプロパティを直接参照し、ダークモードの配色切り替えに追従させる。
  LINE_COLOR = "var(--color-series-asset)"

  # 資産推移(合計資産)の折れ線グラフをインラインSVGで描画する。
  # snapshots は記録日の昇順(古い→新しい)で渡すこと。
  # y軸は横スクロールしても左端に固定されるよう、y軸専用のSVGとグラフ本体のSVGを
  # 分けて描画し、本体側だけをスクロール可能なdivで囲む。
  def asset_trend_svg(snapshots)
    return content_tag(:p, "この期間のスナップショットが2件未満のため、グラフは表示されません。") if snapshots.size < 2

    totals = snapshots.map(&:total_balance)
    min_value, max_value = nice_axis_domain(totals.min, totals.max, step: Y_TICK_STEP, min_span: Y_MIN_SPAN)
    ticks = y_axis_ticks(min_value: min_value, max_value: max_value, step: Y_TICK_STEP,
                          height: CHART_HEIGHT, padding_top: CHART_PADDING_TOP, padding_bottom: CHART_PADDING_BOTTOM)

    body_width = [BODY_MIN_WIDTH, DEFAULT_PADDING + CHART_PADDING_RIGHT + ((snapshots.size - 1) * POINT_SPACING)].max
    points_list = scaled_line_chart_points(
      [totals], width: body_width, height: CHART_HEIGHT,
      padding_left: DEFAULT_PADDING, padding_right: CHART_PADDING_RIGHT,
      padding_top: CHART_PADDING_TOP, padding_bottom: CHART_PADDING_BOTTOM,
      min_value: min_value, max_value: max_value
    )

    body_axes = svg_chart_body_axes(
      width: body_width, height: CHART_HEIGHT,
      padding_left: DEFAULT_PADDING, padding_right: CHART_PADDING_RIGHT, padding_bottom: CHART_PADDING_BOTTOM,
      ticks: ticks, x_labels: thin_labels(snapshots.map { |s| s.recorded_on.strftime("%y/%m") })
    )
    series = svg_line_series(points_list.first, LINE_COLOR) do |index|
      tag.title("#{snapshots[index].recorded_on}: #{number_to_currency(totals[index], unit: '¥', precision: 0)}")
    end
    body_svg = content_tag(:svg, body_axes + series, width: body_width, height: CHART_HEIGHT, viewBox: "0 0 #{body_width} #{CHART_HEIGHT}")

    y_axis_svg = svg_y_axis(width: Y_AXIS_WIDTH, height: CHART_HEIGHT, ticks: ticks,
                             value_formatter: ->(v) { number_to_currency(v, unit: "¥", precision: 0) })

    content_tag(:div, class: "chart-with-fixed-axis") do
      y_axis_svg + content_tag(:div, body_svg, class: "card-scroll")
    end
  end
end
