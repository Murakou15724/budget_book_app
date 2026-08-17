# 追加のJSライブラリを使わず、折れ線グラフをインラインSVGで描画するための共通の
# 座標計算・描画ロジック。AssetSnapshotsHelper/DashboardHelperから利用する。
module SvgLineChartHelper
  DEFAULT_PADDING = 24

  # values_list([[v1, v2, ...], ...])の各系列を共通のスケールでプロットする座標を計算する。
  # baseline: :zero なら0を起点に、:min なら全系列の最小値を起点にスケーリングする
  # (値の変動幅が小さいデータを見やすくしたい場合は :min を使う)。
  # 描画可能な値がない場合(系列が空、または:zeroで全値が0)はnilを返す。
  def scaled_line_chart_points(values_list, width:, height:, baseline: :zero, padding: DEFAULT_PADDING)
    all_values = values_list.flatten
    return nil if all_values.empty?

    max_value = all_values.max
    return nil if max_value.zero? && baseline == :zero

    min_value = baseline == :zero ? 0 : all_values.min
    range = (max_value - min_value).nonzero? || 1

    usable_width = width - (padding * 2)
    usable_height = height - (padding * 2)
    count = values_list.map(&:size).max
    step_x = count > 1 ? usable_width.to_f / (count - 1) : 0

    values_list.map do |values|
      values.each_with_index.map do |value, index|
        x = padding + (step_x * index)
        y = padding + usable_height - ((value - min_value).to_f / range * usable_height)
        [x.round(1), y.round(1)]
      end
    end
  end

  # 1系列分の折れ線(polyline)と各点の丸(circle)を描画する。ブロックは点のindexを受け取り、
  # tag.titleなどのツールチップ要素を返すこと。
  # colorはCSSカスタムプロパティ参照(例: "var(--color-series-income)")を想定しており、
  # style属性経由で適用することでダークモードの配色切り替えに追従させる
  # (fill/stroke属性はvar()を解釈できないため使わない)。
  def svg_line_series(points, color)
    polyline = tag.polyline(points: points.map { |x, y| "#{x},#{y}" }.join(" "), style: "fill: none; stroke: #{color}; stroke-width: 2")
    circles = points.each_with_index.map do |(x, y), index|
      tag.circle(cx: x, cy: y, r: 3, style: "fill: #{color}") { yield(index) }
    end.join.html_safe
    polyline + circles
  end
end
