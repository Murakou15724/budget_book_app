module AssetSnapshotsHelper
  include SvgLineChartHelper

  CHART_HEIGHT = 160
  CHART_PADDING_TOP = 16
  CHART_PADDING_BOTTOM = 32
  # 「¥500,000」ではなく「50万」表記にして目盛ラベルを短くすることで、y軸(固定幅)を
  # 狭く抑えている。
  Y_AXIS_WIDTH = 52
  Y_TICK_STEP = 250_000
  Y_MIN_SPAN = 500_000

  # CSSカスタムプロパティを直接参照し、ダークモードの配色切り替えに追従させる。
  LINE_COLOR = "var(--color-series-asset)"
  # 点同士が密集してホバーで個別の値を判別できなくなるのを防ぐための、点間の最低幅(px)。
  # 「全期間」表示等でスナップショット数が多いときだけ横スクロールが発生する
  # (#fluid_svg_style参照。通常のスマホ幅程度の点数では今まで通り横スクロールなし)。
  MIN_POINT_SPACING = 28

  # 資産推移(合計資産)の折れ線グラフをインラインSVGで描画する。
  # snapshots は記録日の昇順(古い→新しい)で渡すこと。
  # y軸は固定幅(px)で左端に表示し、グラフ本体はコンテナの幅いっぱいに追従させる
  # (通常のスマホ〜PC幅・点数では横スクロールなしで収まる。
  #  「全期間」表示等で点数が多く密集する場合のみMIN_POINT_SPACINGにより横スクロールする)。
  def asset_trend_svg(snapshots)
    return content_tag(:p, "この期間のスナップショットが2件未満のため、グラフは表示されません。") if snapshots.size < 2

    totals = snapshots.map(&:total_balance)
    min_value, max_value = nice_axis_domain(totals.min, totals.max, step: Y_TICK_STEP, min_span: Y_MIN_SPAN)
    ticks = y_axis_ticks(min_value: min_value, max_value: max_value, step: Y_TICK_STEP,
                          height: CHART_HEIGHT, padding_top: CHART_PADDING_TOP, padding_bottom: CHART_PADDING_BOTTOM)

    points = fluid_line_points([totals], height: CHART_HEIGHT, padding_top: CHART_PADDING_TOP, padding_bottom: CHART_PADDING_BOTTOM,
                                min_value: min_value, max_value: max_value).first

    body_axes = svg_chart_body_axes(height: CHART_HEIGHT, padding_bottom: CHART_PADDING_BOTTOM,
                                     ticks: ticks, x_labels: thin_labels(snapshots.map { |s| s.recorded_on.strftime("%y/%m") }))
    series = fluid_line_series(points, LINE_COLOR) do |index|
      tag.title("#{snapshots[index].recorded_on}: #{number_to_currency(totals[index], unit: '¥', precision: 0)}")
    end
    body_svg = content_tag(:svg, body_axes + series, height: CHART_HEIGHT,
                            style: fluid_svg_style(min_width_px: snapshots.size * MIN_POINT_SPACING))

    y_axis_svg = svg_y_axis(width: Y_AXIS_WIDTH, height: CHART_HEIGHT, ticks: ticks,
                             value_formatter: ->(v) { "#{(v / 10_000).round}万" })

    content_tag(:div, class: "chart-with-fixed-axis") do
      y_axis_svg + content_tag(:div, body_svg, class: "chart-body")
    end
  end
end
