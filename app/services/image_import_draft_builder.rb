# Gemini::TransactionExtractorの抽出結果(Hashの配列)から、レビュー画面用のImageImportDraftを作成する。
class ImageImportDraftBuilder
  def self.build(items)
    new.build(items)
  end

  def build(items)
    batch_id = SecureRandom.uuid
    drafts = items.map { |item| build_draft(item, batch_id) }
    [batch_id, drafts]
  end

  private

  def build_draft(item, batch_id)
    direction = item["direction"] == "income" ? :income : :expense
    category = find_master(Category.where(kind: direction), item["category_name"])
    payment_method = find_master(PaymentMethod.all, item["payment_method_name"])
    account = find_master(Account.all, item["account_name"])

    # 要件定義書のクレカ運用ルール(利用時は支払状況=未払)に合わせ、
    # 口座が「クレカ仮置き」と突合できた場合はGeminiの判定に頼らず機械的に導出する。
    credit_card_status = account&.credit_pending? ? :unpaid : :not_applicable

    ImageImportDraft.create!(
      batch_id: batch_id,
      date: parse_date(item["date"]),
      direction: direction,
      amount: item["amount"],
      memo: item["memo"],
      category: category,
      payment_method: payment_method,
      account: account,
      credit_card_status: credit_card_status,
      suggested_category_name: category ? nil : item["category_name"],
      suggested_payment_method_name: payment_method ? nil : item["payment_method_name"],
      suggested_account_name: account ? nil : item["account_name"]
    )
  end

  def find_master(scope, name)
    return nil if name.blank?

    scope.find_by("LOWER(name) = ?", name.to_s.downcase)
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError
    nil
  end
end
