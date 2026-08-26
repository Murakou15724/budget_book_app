module AssetSnapshotsHelper
  include SvgLineChartHelper

  CHART_WIDTH = 640
  CHART_HEIGHT = 160
  CHART_PADDING_LEFT = 76
  CHART_PADDING_BOTTOM = 32

  # CSSカスタムプロパティを直接参照し、ダークモードの配色切り替えに追従させる。
  LINE_COLOR = "var(--color-series-asset)"

  # 資産推移(合計資産)の折れ線グラフをインラインSVGで描画する。
  # snapshots は記録日の昇順(古い→新しい)で渡すこと。
  def asset_trend_svg(snapshots)
    return content_tag(:p, "資産スナップショットを2件以上登録するとグラフが表示されます。") if snapshots.size < 2

    totals = snapshots.map(&:total_balance)
    points_list = scaled_line_chart_points(
      [totals], width: CHART_WIDTH, height: CHART_HEIGHT, baseline: :min,
      padding: DEFAULT_PADDING, padding_left: CHART_PADDING_LEFT, padding_bottom: CHART_PADDING_BOTTOM
    )
    return content_tag(:p, "資産スナップショットを2件以上登録するとグラフが表示されます。") if points_list.nil?

    axes = svg_chart_axes(
      width: CHART_WIDTH, height: CHART_HEIGHT, min_value: totals.min, max_value: totals.max,
      padding_left: CHART_PADDING_LEFT, padding_right: DEFAULT_PADDING,
      padding_top: DEFAULT_PADDING, padding_bottom: CHART_PADDING_BOTTOM,
      x_labels: thin_labels(snapshots.map { |s| s.recorded_on.strftime("%y/%m") }),
      value_formatter: ->(v) { number_to_currency(v, unit: "¥", precision: 0) }
    )
    series = svg_line_series(points_list.first, LINE_COLOR) do |index|
      tag.title("#{snapshots[index].recorded_on}: #{number_to_currency(totals[index], unit: '¥', precision: 0)}")
    end

    content_tag(:svg, width: CHART_WIDTH, height: CHART_HEIGHT, viewBox: "0 0 #{CHART_WIDTH} #{CHART_HEIGHT}") { axes + series }
  end
end
