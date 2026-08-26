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
  # min_value/max_valueを明示的に渡すと、系列の実データから自動計算する代わりに
  # そのスケールでプロットする(#nice_axis_domainで求めた「ちょうどいい」軸幅を使う場合など)。
  def scaled_line_chart_points(values_list, width:, height:, baseline: :zero, padding: DEFAULT_PADDING,
                                padding_left: padding, padding_right: padding,
                                padding_top: padding, padding_bottom: padding,
                                min_value: nil, max_value: nil)
    all_values = values_list.flatten
    return nil if all_values.empty?

    max_value ||= all_values.max
    return nil if max_value.zero? && baseline == :zero && min_value.nil?

    min_value ||= (baseline == :zero ? 0 : all_values.min)
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

  # データの最小値/最大値をstep単位に切り下げ/切り上げして「ちょうどいい」軸の
  # 上下限を求める。幅がmin_span未満の場合は両端をstep単位で広げてmin_span以上を確保する
  # (値の変動が小さい期間でもグラフが極端に間延びしたり潰れたりしないようにするため)。
  # anchor_zero: trueの場合は下限を常に0に固定し、上限だけをstep単位に広げる
  # (収入・支出・カテゴリ別支出額など、負の値を取らずグラフを0始点にしたい系列向け)。
  def nice_axis_domain(min_value, max_value, step:, min_span:, anchor_zero: false)
    if anchor_zero
      upper = (max_value.to_f / step).ceil * step
      upper = step if upper.zero?
      upper = min_span if upper < min_span
      return [0, upper]
    end

    lower = (min_value.to_f / step).floor * step
    upper = (max_value.to_f / step).ceil * step
    upper = lower + step if upper <= lower

    while upper - lower < min_span
      lower -= step
      upper += step
    end

    [lower, upper]
  end

  # y軸の目盛(値とSVG上のy座標)を計算する。配列の先頭が下(最小値)、末尾が上(最大値)。
  # 固定表示側(#svg_y_axis)とスクロール側(#svg_chart_body_axes)の両方で同じ目盛位置を
  # 使うことで、横スクロールしてもy軸の目盛線と位置がずれないようにする。
  def y_axis_ticks(min_value:, max_value:, step:, height:, padding_top:, padding_bottom:)
    usable_height = height - padding_top - padding_bottom
    tick_count = ((max_value - min_value) / step).round

    (0..tick_count).map do |i|
      ratio = tick_count.zero? ? 0 : i.to_f / tick_count
      y = (padding_top + usable_height - (usable_height * ratio)).round(1)
      { value: min_value + (step * i), y: y }
    end
  end

  # y軸(左端に固定表示する側)のSVGを組み立てる。目盛線本体はスクロールする側
  # (#svg_chart_body_axes)に描画し、ここでは短い目盛マーク+ラベル+縦の軸線のみを描く。
  def svg_y_axis(width:, height:, ticks:, value_formatter:)
    axis_x = width - 1

    marks_and_labels = ticks.map do |tick|
      mark = tag.line(x1: axis_x - 4, y1: tick[:y], x2: axis_x, y2: tick[:y], class: "chart-axis-line")
      label = tag.text(value_formatter.call(tick[:value]), x: axis_x - 8, y: tick[:y] + 3, "text-anchor": "end", class: "chart-axis-label")
      mark + label
    end.join.html_safe

    axis_line = tag.line(x1: axis_x, y1: ticks.first[:y], x2: axis_x, y2: ticks.last[:y], class: "chart-axis-line")

    content_tag(:svg, marks_and_labels + axis_line, width: width, height: height, viewBox: "0 0 #{width} #{height}", class: "chart-y-axis")
  end

  # y軸の目盛線(横方向の破線)だけを描画する。折れ線グラフ本体(#svg_chart_body_axes)の
  # ほか、x軸ラベルの描き方が異なる棒グラフ(回転ラベルなど)からも個別に利用する。
  def svg_gridlines(padding_left:, axis_right:, ticks:)
    ticks.map do |tick|
      tag.line(x1: padding_left, y1: tick[:y], x2: axis_right, y2: tick[:y], class: "chart-gridline")
    end.join.html_safe
  end

  # グラフ本体(スクロールする側)の横方向目盛線・x軸線・x軸ラベルを描画する。
  # svg_line_seriesの出力と組み合わせて<svg>の中身として使うこと。
  # x_labelsは点ごとのラベル文字列の配列(要素数は点の数と揃える)。nil/空文字の要素は
  # ラベルを描画しない(#thin_labelsで間引いたラベルを渡す想定)。
  def svg_chart_body_axes(width:, height:, padding_left:, padding_right:, padding_bottom:, ticks:, x_labels:)
    usable_width = width - padding_left - padding_right
    axis_bottom = height - padding_bottom
    axis_right = padding_left + usable_width

    gridlines = svg_gridlines(padding_left: padding_left, axis_right: axis_right, ticks: ticks)

    x_axis_line = tag.line(x1: padding_left, y1: axis_bottom, x2: axis_right, y2: axis_bottom, class: "chart-axis-line")

    count = x_labels.size
    step_x = count > 1 ? usable_width.to_f / (count - 1) : 0
    x_tick_labels = x_labels.each_with_index.filter_map do |label, index|
      next if label.blank?

      x = (padding_left + (step_x * index)).round(1)
      tag.text(label, x: x, y: axis_bottom + 16, "text-anchor": "middle", class: "chart-axis-label")
    end.join.html_safe

    gridlines + x_axis_line + x_tick_labels
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
