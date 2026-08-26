# 追加のJSライブラリを使わず、折れ線グラフをインラインSVGで描画するための共通の
# 座標計算・描画ロジック。AssetSnapshotsHelper/DashboardHelperから利用する。
module SvgLineChartHelper
  DEFAULT_PADDING = 24

  # values_list([[v1, v2, ...], ...])の各系列を共通のスケールでプロットする座標を計算する。
  # baseline: :zero なら0を起点に、:min なら全系列の最小値を起点にスケーリングする
  # (値の変動幅が小さいデータを見やすくしたい場合は :min を使う)。
  # padding_*を個別に指定すると、軸ラベル分だけ左/下の余白を広げるといった使い方ができる
  # (未指定の場合はpaddingの値がそのまま使われ、従来の挙動と互換)。
  # 描画可能な値がない場合(系列が空、または:zeroで全値が0)はnilを返す。
  def scaled_line_chart_points(values_list, width:, height:, baseline: :zero, padding: DEFAULT_PADDING,
                                padding_left: padding, padding_right: padding,
                                padding_top: padding, padding_bottom: padding)
    all_values = values_list.flatten
    return nil if all_values.empty?

    max_value = all_values.max
    return nil if max_value.zero? && baseline == :zero

    min_value = baseline == :zero ? 0 : all_values.min
    range = (max_value - min_value).nonzero? || 1

    usable_width = width - padding_left - padding_right
    usable_height = height - padding_top - padding_bottom
    count = values_list.map(&:size).max
    step_x = count > 1 ? usable_width.to_f / (count - 1) : 0

    values_list.map do |values|
      values.each_with_index.map do |value, index|
        x = padding_left + (step_x * index)
        y = padding_top + usable_height - ((value - min_value).to_f / range * usable_height)
        [x.round(1), y.round(1)]
      end
    end
  end

  # 折れ線グラフの軸線・目盛線(横方向)・目盛ラベル(x軸・y軸)を描画する。
  # x_labelsは点ごとのラベル文字列の配列(要素数は点の数と揃える)。nil/空文字の要素は
  # ラベルを描画しない(#thin_labelsで間引いたラベルを渡す想定)。
  def svg_chart_axes(width:, height:, min_value:, max_value:,
                      padding_left:, padding_right:, padding_top:, padding_bottom:,
                      x_labels:, y_tick_count: 4, value_formatter: ->(v) { v.round.to_s })
    usable_width = width - padding_left - padding_right
    usable_height = height - padding_top - padding_bottom
    axis_bottom = padding_top + usable_height
    axis_right = padding_left + usable_width
    range = (max_value - min_value).nonzero? || 1

    gridlines = (0..y_tick_count).map do |i|
      ratio = i.to_f / y_tick_count
      value = min_value + (range * ratio)
      y = (axis_bottom - (usable_height * ratio)).round(1)

      line = tag.line(x1: padding_left, y1: y, x2: axis_right, y2: y, class: "chart-gridline")
      label = tag.text(value_formatter.call(value), x: padding_left - 6, y: y + 3, "text-anchor": "end", class: "chart-axis-label")
      line + label
    end.join.html_safe

    axes = tag.line(x1: padding_left, y1: padding_top, x2: padding_left, y2: axis_bottom, class: "chart-axis-line") +
           tag.line(x1: padding_left, y1: axis_bottom, x2: axis_right, y2: axis_bottom, class: "chart-axis-line")

    count = x_labels.size
    step_x = count > 1 ? usable_width.to_f / (count - 1) : 0
    x_tick_labels = x_labels.each_with_index.filter_map do |label, index|
      next if label.blank?

      x = (padding_left + (step_x * index)).round(1)
      tag.text(label, x: x, y: axis_bottom + 16, "text-anchor": "middle", class: "chart-axis-label")
    end.join.html_safe

    gridlines + axes + x_tick_labels
  end

  # ラベル数が多いグラフでx軸の文字が重なるのを避けるため、表示するラベルを均等に
  # 間引く(先頭・末尾は必ず残す)。間引かれた位置はnilにする。さらに、間引き後に
  # 隣り合う同じラベル(例: 同じ月の日付が複数残った場合の"26/06"の連続)が残ると
  # 見た目上重複表示になるため、直前と同じラベルはnilにする。
  def thin_labels(labels, max: 6)
    thinned =
      if labels.size <= max
        labels
      else
        step = (labels.size - 1).to_f / (max - 1)
        keep_indices = (0...max).map { |i| (i * step).round }.uniq
        labels.each_with_index.map { |label, index| keep_indices.include?(index) ? label : nil }
      end

    dedupe_adjacent_labels(thinned)
  end

  def dedupe_adjacent_labels(labels)
    last_shown = nil
    labels.map do |label|
      next nil if label.blank?

      if label == last_shown
        nil
      else
        last_shown = label
        label
      end
    end
  end
  private :dedupe_adjacent_labels

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
