# 追加のJSライブラリを使わず、折れ線グラフ/棒グラフをインラインSVGで描画するための
# 共通の座標計算・描画ロジック。AssetSnapshotsHelper/DashboardHelperから利用する。
#
# グラフ本体はviewBoxで丸ごと拡大縮小するのではなく、x座標を%指定・y座標(や文字サイズ・
# 線の太さ)はpx指定にすることで、コンテナの幅(スマホ〜PC)に応じて左右いっぱいに
# 追従させつつ、文字や線がデバイス幅によって拡大縮小されないようにしている。
module SvgLineChartHelper
  # SVGは既定でビューポート外の描画をクリップするため、0%/100%際の点やラベルが
  # 半端に切れないようにoverflowを可視化し、幅はCSSでコンテナいっぱいに広げる。
  FLUID_SVG_STYLE = "width: 100%; display: block; overflow: visible;"

  # 通常は横スクロール無しでコンテナ幅いっぱいに収まる可変サイズを優先するが、
  # 項目数・点数が多いときにバー/点が潰れて読めなくなるのを避けるため、
  # 1項目あたりの最低幅(min-width)を指定できるようにする。項目数が少ない間は
  # 何も変わらず、min-widthがコンテナ幅を超えた場合だけ横スクロールが発生する。
  def fluid_svg_style(min_width_px: nil)
    return FLUID_SVG_STYLE if min_width_px.nil?

    "#{FLUID_SVG_STYLE} min-width: #{min_width_px}px;"
  end

  # 系列(values_listの各配列)のプロット座標を計算する。xはコンテナ幅に対する
  # 割合(0〜100のパーセント数値)、yはpx(数値)。
  # baseline: :zero なら0を起点に、:min なら全系列の最小値を起点にスケーリングする
  # (値の変動幅が小さいデータを見やすくしたい場合は :min を使う)。
  # min_value/max_valueを明示的に渡すと、系列の実データから自動計算する代わりに
  # そのスケールでプロットする(#nice_axis_domainで求めた「ちょうどいい」軸幅を使う場合など)。
  # 描画可能な値がない場合(系列が空、または:zeroで全値が0)はnilを返す。
  def fluid_line_points(values_list, height:, padding_top:, padding_bottom:, baseline: :zero, min_value: nil, max_value: nil)
    all_values = values_list.flatten
    return nil if all_values.empty?

    max_value ||= all_values.max
    return nil if max_value.zero? && baseline == :zero && min_value.nil?

    min_value ||= (baseline == :zero ? 0 : all_values.min)
    range = (max_value - min_value).nonzero? || 1
    usable_height = height - padding_top - padding_bottom
    count = values_list.map(&:size).max

    values_list.map do |values|
      values.each_with_index.map do |value, index|
        x_percent = count > 1 ? (index.to_f / (count - 1) * 100).round(2) : 50.0
        y = (padding_top + usable_height - ((value - min_value).to_f / range * usable_height)).round(1)
        [x_percent, y]
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
  # 固定表示側(#svg_y_axis)とグラフ本体側(#svg_chart_body_axes)の両方で同じ目盛位置を
  # 使うことで、y軸の目盛線と位置がずれないようにする。
  def y_axis_ticks(min_value:, max_value:, step:, height:, padding_top:, padding_bottom:)
    usable_height = height - padding_top - padding_bottom
    tick_count = ((max_value - min_value) / step).round

    (0..tick_count).map do |i|
      ratio = tick_count.zero? ? 0 : i.to_f / tick_count
      y = (padding_top + usable_height - (usable_height * ratio)).round(1)
      { value: min_value + (step * i), y: y }
    end
  end

  # y軸(左端に固定表示する側)のSVGを組み立てる。目盛線本体はグラフ本体側
  # (#svg_chart_body_axes)に描画し、ここでは短い目盛マーク+ラベル+縦の軸線のみを描く。
  # 固定の狭い幅のまま常にpx単位で描くため、コンテナ幅が変わっても拡大縮小されない。
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

  # y軸の目盛線(横方向の破線)を、コンテナ幅いっぱい(0%〜100%)に描画する。
  def svg_gridlines(ticks:)
    ticks.map do |tick|
      tag.line(x1: "0%", y1: tick[:y], x2: "100%", y2: tick[:y], class: "chart-gridline")
    end.join.html_safe
  end

  # グラフ本体(幅いっぱいに追従する側)の横方向目盛線・x軸線・x軸ラベルを描画する。
  # #fluid_line_seriesの出力と組み合わせて<svg>の中身として使うこと。
  # x_labelsは点ごとのラベル文字列の配列(要素数は点の数と揃える)。nil/空文字の要素は
  # ラベルを描画しない(#thin_labelsで間引いたラベルを渡す想定)。
  def svg_chart_body_axes(height:, padding_bottom:, ticks:, x_labels:)
    axis_bottom = height - padding_bottom

    gridlines = svg_gridlines(ticks: ticks)
    x_axis_line = tag.line(x1: "0%", y1: axis_bottom, x2: "100%", y2: axis_bottom, class: "chart-axis-line")

    count = x_labels.size
    x_tick_labels = x_labels.each_with_index.filter_map do |label, index|
      next if label.blank?

      x_percent = count > 1 ? (index.to_f / (count - 1) * 100).round(2) : 50.0
      tag.text(label, x: "#{x_percent}%", y: axis_bottom + 16, "text-anchor": "middle", class: "chart-axis-label")
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

  # 1系列分の折れ線+各点の丸を描画する。ブロックは点のindexを受け取り、tag.titleなどの
  # ツールチップ要素を返すこと。xが%指定のため<polyline points="...">は使えない
  # (points属性は%を扱えない)。代わりに隣接点同士を結ぶ<line>を連結する。
  # colorはCSSカスタムプロパティ参照(例: "var(--color-series-income)")を想定しており、
  # style属性経由で適用することでダークモードの配色切り替えに追従させる
  # (fill/stroke属性はvar()を解釈できないため使わない)。
  def fluid_line_series(points, color)
    segments = points.each_cons(2).map do |(x1, y1), (x2, y2)|
      tag.line(x1: "#{x1}%", y1: y1, x2: "#{x2}%", y2: y2, style: "stroke: #{color}; stroke-width: 2")
    end.join.html_safe

    circles = points.each_with_index.map do |(x, y), index|
      tag.circle(cx: "#{x}%", cy: y, r: 3, style: "fill: #{color}") { yield(index) }
    end.join.html_safe

    segments + circles
  end
end
