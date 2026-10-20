# Gemini::TransactionExtractorの抽出結果(Hashの配列)から、レビュー画面用のImageImportDraftを作成する。
class ImageImportDraftBuilder
  def self.build(items, document:, manual_date: nil)
    new.build(items, document: document, manual_date: manual_date)
  end

  def build(items, document:, manual_date: nil)
    ImportGuard.synchronize do
      document.lock!
      drafts = items.each_with_index.map { |item, index| build_draft(item, document, index + 1, manual_date) }
      drafts.each { |draft| Imports::Matcher.classify!(draft.import_entry) }
      [document.batch_id, drafts]
    end
  end

  private

  def build_draft(item, document, row_number, manual_date)
    direction = item["direction"] == "income" ? :income : :expense
    category = find_master(Category.where(kind: direction), item["category_name"])
    payment_method = find_master(PaymentMethod.all, item["payment_method_name"])
    account = find_master(Account.all, item["account_name"])

    # 要件定義書のクレカ運用ルール(利用時は支払状況=未払)に合わせ、
    # 口座が「クレカ仮置き」と突合できた場合はGeminiの判定に頼らず機械的に導出する。
    credit_card_status = account&.credit_pending? ? :unpaid : :not_applicable

    # 日付の優先度: 手動指定 > 画像内から特定 > アップロード日
    date = manual_date || document.manual_date || parse_date(item["date"]) || document.fallback_date

    entry = Imports::EntryRecorder.call(document: document, row_number: row_number, payload: item, draft_attributes: {
      date: date,
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
    })
    entry.image_import_draft
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
