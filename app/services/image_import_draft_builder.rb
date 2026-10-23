# Gemini::TransactionExtractorの抽出結果(Hashの配列)から、レビュー画面用のImageImportDraftを作成する。
class ImageImportDraftBuilder
  def self.build(items, document:, manual_date: nil)
    new.build(items, document: document, manual_date: manual_date)
  end

  def build(items, document:, manual_date: nil)
    ImportGuard.synchronize do
      document.lock!
      drafts = items.each_with_index.map { |item, index| build_draft(item, document, index + 1, manual_date) }
      drafts.each do |draft|
        Imports::RuleResolver.call(entry: draft.import_entry, draft: draft) if draft.rule_decision.empty?
      end
      drafts.each { |draft| Imports::Matcher.classify!(draft.import_entry) }
      [document.batch_id, drafts]
    end
  end

  private

  def build_draft(item, document, row_number, manual_date)
    item = item.stringify_keys
    direction = %w[income expense transfer investment].include?(item["direction"]) ? item["direction"] : nil
    category = %w[income expense].include?(direction) && find_master(Category.where(kind: direction), item["category_name"])
    payment_method = find_master(PaymentMethod.all, item["payment_method_name"])
    account = find_master(Account.all, item["account_name"])
    credit_card_status = account&.credit_pending? ? :unpaid : :not_applicable
    user_date = Imports::StrictDate.parse(manual_date || document.manual_date)
    source_date = Imports::StrictDate.source(item)
    date = user_date || source_date
    origin = user_date ? "user" : (source_date ? "source" : "unresolved")
    evidence = item["evidence"].is_a?(Hash) ? item["evidence"].slice("amount", "direction", "transaction_kind", "merchant").transform_values { |v| v.is_a?(String) ? v.first(255) : nil } : {}
    kind = Imports::TransactionKindClassifier.call(payload: item.merge("evidence" => evidence))
    metadata = { "version" => 1, "evidence" => evidence, "raw_date" => item["raw_date"],
      "uncertain_fields" => item["uncertain_fields"].is_a?(Array) ? item["uncertain_fields"] : nil, "source_kind" => kind }

    entry = Imports::EntryRecorder.call(document: document, row_number: row_number, payload: item, draft_attributes: {
      date: date,
      direction: direction,
      amount: item["amount"].is_a?(Integer) && item["amount"].between?(-2**31, 2**31 - 1) ? item["amount"] : nil,
      date_origin: origin, transaction_kind: kind, confirmation_metadata: metadata, rule_decision: {},
      memo: item["memo"].to_s.first(255),
      category: category || nil,
      payment_method: payment_method,
      account: account,
      credit_card_status: credit_card_status,
      suggested_category_name: category ? nil : item["category_name"].to_s.first(255),
      suggested_payment_method_name: payment_method ? nil : item["payment_method_name"],
      suggested_account_name: account ? nil : item["account_name"]
    })
    entry.image_import_draft
  end

  def find_master(scope, name)
    return nil if name.blank?

    scope.find_by("LOWER(name) = ?", name.to_s.downcase)
  end

end
