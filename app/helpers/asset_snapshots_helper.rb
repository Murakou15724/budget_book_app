module AssetSnapshotsHelper
  CHART_WIDTH = 640
  CHART_HEIGHT = 160
  CHART_PADDING = 24

  # 追加のJSライブラリを使わず、資産推移(合計資産)の折れ線グラフをインラインSVGで描画する。
  # snapshots は記録日の昇順(古い→新しい)で渡すこと。
  def asset_trend_svg(snapshots)
    return content_tag(:p, "資産スナップショットを2件以上登録するとグラフが表示されます。") if snapshots.size < 2

    totals = snapshots.map(&:total_balance)
    min_total = totals.min
    max_total = totals.max
    range = (max_total - min_total).nonzero? || 1

    usable_width = CHART_WIDTH - (CHART_PADDING * 2)
    usable_height = CHART_HEIGHT - (CHART_PADDING * 2)
    step_x = snapshots.size > 1 ? usable_width.to_f / (snapshots.size - 1) : 0

    points = totals.each_with_index.map do |total, index|
      x = CHART_PADDING + (step_x * index)
      y = CHART_PADDING + usable_height - ((total - min_total).to_f / range * usable_height)
      [x.round(1), y.round(1)]
    end

    polyline_points = points.map { |x, y| "#{x},#{y}" }.join(" ")

    circles = snapshots.each_with_index.map do |snapshot, index|
      x, y = points[index]
      tag.circle(cx: x, cy: y, r: 3, fill: "#2f3e46") do
        tag.title("#{snapshot.recorded_on}: #{number_to_currency(totals[index], unit: '¥', precision: 0)}")
      end
    end.join.html_safe

    content_tag(:svg, width: CHART_WIDTH, height: CHART_HEIGHT, viewBox: "0 0 #{CHART_WIDTH} #{CHART_HEIGHT}") do
      tag.polyline(points: polyline_points, fill: "none", stroke: "#2f3e46", "stroke-width": 2) + circles
    end
  end
end
