module ImportsHelper
  KIND_LABELS = { "normal" => "通常取引", "charge" => "チャージ", "transfer" => "口座間移動", "investment" => "投資", "card_settlement" => "カード引落", "refund" => "返金", "cancellation" => "取消", "fee" => "手数料", "unknown" => "未確定" }.freeze
  REASONS = {
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
    "category_id" => "カテゴリ", "payment_method_id" => "支払方法", "account_id" => "反映口座", "to_account_id" => "移動先口座",
    "memo" => "メモ", "merchant" => "取引先", "currency" => "通貨", "source_status" => "元明細の状態",
    "category_name" => "推定カテゴリ", "payment_method_name" => "推定支払方法", "account_name" => "推定口座",
    "credit_card_status" => "クレカ支払状況", "credit_card_paid_on" => "引落日",
    "credit_card_payment_due_on_override" => "支払予定日の指定", "satisfaction" => "満足度", "regret" => "後悔" }.freeze
  ACTIONS = { "distinct" => "別取引として登録", "link" => "同一取引として対応付け", "adopt_revision" => "この訂正版を初回採用",
    "acknowledge_current" => "現行内容で対応を維持", "acknowledge_deleted" => "削除を確認して再登録しない" }.freeze
  STATES = { "pending" => "未確定", "held" => "保留", "conflict" => "要確認", "applied" => "反映済", "linked" => "対応付け済",
    "rejected" => "却下", "superseded" => "訂正版へ引継ぎ", "deletion_acknowledged" => "削除確認済み", "reference" => "代表候補を参照" }.freeze

  def import_reason_label(reason)
    REASONS.fetch(reason, reason.presence || "新規候補")
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
