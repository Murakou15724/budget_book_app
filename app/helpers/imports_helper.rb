module ImportsHelper
  KIND_LABELS = { "normal" => "通常取引", "charge" => "チャージ", "transfer" => "口座間移動", "investment" => "投資", "card_settlement" => "カード引落", "refund" => "返金", "cancellation" => "取消", "fee" => "手数料", "unknown" => "未確定" }.freeze
  REASONS = {
    "csv_source" => "PayPayの取込元を選択してください", "csv_file" => "CSVファイルを1件選択してください",
    "csv_too_large" => "CSVは8MiBまでです。ファイルを分割してください", "csv_encoding" => "UTF-8のCSVを指定してください",
    "csv_nul" => "NULを含むCSVは読み込めません", "csv_empty" => "CSVが空です", "csv_headers" => "公式13列の見出しを過不足・重複なく指定してください",
    "csv_columns" => "列数が13列ではありません", "csv_too_many_rows" => "CSVは1,000行までです。ファイルを分割してください",
    "csv_syntax" => "CSVの引用符・改行等の構文が不正です", "csv_date" => "取引日時が欠落・不正です（2000〜2099年の日本時間）",
    "csv_amount" => "円金額が整数ではないか桁区切りが不正です", "csv_amount_direction" => "入金・出金のいずれか一方に正額が必要です",
    "csv_amount_range" => "円金額が反映可能な範囲を超えています", "csv_external_id" => "取引番号が空か制御文字を含みます",
    "csv_required" => "取引内容・取引先・取引方法に空欄があります", "csv_merchant_length" => "取引先が255文字を超えるためルールを適用しません",
    "csv_foreign" => "外貨・利用国・レート等を含むため円取引として反映しません", "csv_points" => "ポイントを含む取引です",
    "csv_mixed_method" => "複数の取引方法を含むため確認が必要です", "csv_payment_type" => "支払い区分が対応条件外です",
    "csv_user" => "利用者の確認が必要です", "csv_content_direction" => "取引内容と入出金が矛盾しています",
    "csv_special" => "通常の支払い・給与以外のため確認が必要です", "csv_route_missing" => "取引方法の支払経路が未設定です",
    "csv_route_disabled" => "CSV支払経路が停止されています", "csv_route_collision" => "取引方法の識別子が衝突しています",
    "csv_route_changed" => "取込後に支払経路が変更されました", "processing_failed" => "処理に失敗しました。履歴を確認してください",
    "reference_rejected" => "代表候補は却下済み（実績の重複ではありません）", "reference_pending" => "代表候補が未確定です",
    "reference_held" => "代表候補が保留中です", "reference_conflict" => "代表候補が要確認です",
    "reference_applied" => "代表候補は反映済み", "reference_linked" => "代表候補は対応済み",
    "reference_superseded" => "代表候補は訂正版へ引継ぎ", "reference_deletion_acknowledged" => "代表候補は削除確認済み",
    "rule_missing" => "確認済みルールがありません", "rule_ambiguous" => "複数のルールが一致しています",
    "rule_invalid" => "ルールの分類・支払経路が不正です", "rule_changed" => "抽出後にルールが変更・停止されました",
    "date_unresolved" => "日付が未確定または不正です", "extraction_evidence_missing" => "原文根拠が不足しています",
    "extraction_uncertain" => "抽出に不確実な項目があります", "special_transaction" => "特殊取引・種別未確定のため手動確認が必要です",
    "payment_route_unconfirmed" => "支払方法の種別が未設定・対象外です", "payment_route_mismatch" => "支払方法・口座・クレカ状態が一致しません",
    "category_direction_mismatch" => "カテゴリの区分と収支が一致しません", "auto_apply_disabled" => "この経路の自動反映は許可されていません",
    "candidate_edited" => "編集済みの候補は自動反映しません", "invalid_planned_target" => "対応先予定の分類・支払経路が不正です。予定を修正して再プレビューしてください",
    "correction_confirmed" => "実績の訂正内容を確認しました",
    "similar_candidates" => "同じ口座・収支・金額で日付±7日の候補があります", "external_id_changed" => "同じ外部IDの内容が変わっています",
    "invalid_transaction" => "必須項目または入力値の修正が必要です", "source_account_mismatch" => "元口座と反映口座が異なります",
    "legacy_origin_unknown" => "移行前の候補のため元画像・元口座は不明です", "target_changed" => "対応先の取引が変更されています",
    "target_deleted" => "対応先の取引が削除されています", "deletion_confirmed" => "削除確認済み・再登録しません",
    "user_rejected" => "利用者が却下しました", "user_held" => "利用者が保留しました", "revision_adopted" => "訂正版を採用しました",
    "current_confirmed" => "現在の取引内容で対応を確認しました"
  }.freeze
  FIELDS = { "date" => "取引日", "occurred_at" => "取引日時", "entry_type" => "入力区分", "direction" => "収支", "amount" => "金額",
    "source_method" => "取引方法原文", "import_payment_route_id" => "CSV支払経路",
    "category_id" => "カテゴリ", "payment_method_id" => "支払方法", "account_id" => "反映口座", "to_account_id" => "移動先口座",
    "memo" => "メモ", "merchant" => "取引先", "currency" => "通貨", "source_status" => "元明細の状態",
    "category_name" => "推定カテゴリ", "payment_method_name" => "推定支払方法", "account_name" => "推定口座",
    "credit_card_status" => "クレカ支払状況", "credit_card_paid_on" => "引落日",
    "credit_card_payment_due_on_override" => "支払予定日の指定", "satisfaction" => "満足度", "regret" => "後悔" }.freeze
  ACTIONS = { "distinct" => "別取引として登録", "link" => "同一取引として対応付け", "adopt_revision" => "この訂正版を初回採用",
    "acknowledge_current" => "現行内容で対応を維持", "acknowledge_deleted" => "削除を確認して再登録しない" }.freeze
  STATES = { "pending" => "未確定", "held" => "保留", "conflict" => "要確認", "applied" => "反映済", "linked" => "対応付け済",
    "rejected" => "却下", "superseded" => "訂正版へ引継ぎ", "deletion_acknowledged" => "削除確認済み", "reference" => "代表候補を参照" }.freeze

  def import_document_summary(document)
    summary = { count: 0, classifications: Hash.new(0), states: {}, automatic: { count: 0, income: 0, expense: 0 }, rules: Hash.new(0) }
    columns = ImportEntry.column_names - ["payload"]
    document.import_entries.select(*columns).includes(:reference_entry, :image_import_draft).find_each(batch_size: 100) do |entry|
      summary[:count] += 1
      summary[:classifications][entry.summary_classification] += 1
      state = summary[:states][entry.effective_entry.state] ||= { count: 0, amount: 0 }
      state[:count] += 1
      state[:amount] += entry.image_import_draft&.amount.to_i
    end
    document.import_events.where(kind: "applied").find_each(batch_size: 100) do |event|
      next unless event.details["mode"] == "automatic"

      summary[:automatic][:count] += 1
      summary[:rules][event.details.dig("rule_decision", "matched_rules")] += 1
      key = event.details["direction"].to_s.to_sym
      summary[:automatic][key] += event.details["amount"].to_i if %i[income expense].include?(key)
    end
    summary
  end

  def import_reason_label(reason)
    REASONS.fetch(reason) { STATES.fetch(reason, reason.presence || "新規候補") }
  end

  def import_state_label(state)
    STATES.fetch(state, state)
  end

  def import_image_number(document)
    mapping = params[:image_numbers]
    return unless mapping.is_a?(ActionController::Parameters)

    numbers = Array(mapping[document.id.to_s]).filter_map { |value| Integer(value, exception: false) }.select(&:positive?).uniq
    numbers.first(100).presence&.join("・")
  end

  def import_value(key, value, snapshot = {})
    return "（なし）" if value.nil?
    return "（空欄）" if value == ""
    return number_to_currency(value, unit: "¥", precision: 0) if key == "amount"
    return Transaction::ENTRY_TYPE_LABELS[value] || value if key == "entry_type"
    return Transaction::DIRECTION_LABELS[value] || value if key == "direction"
    return Transaction::CREDIT_CARD_STATUS_LABELS[value] || value if key == "credit_card_status"
    return value ? "あり" : "なし" if key == "regret"

    masters = { "category_id" => Category, "payment_method_id" => PaymentMethod, "account_id" => Account, "to_account_id" => Account }
    if masters.key?(key)
      name = snapshot.dig("master_names", key.delete_suffix("_id")) || masters.fetch(key).find_by(id: value)&.name
      return "#{name || '削除済み'} (##{value})"
    end
    value
  end
end
