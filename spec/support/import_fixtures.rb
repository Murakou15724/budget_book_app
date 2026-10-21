module ImportFixtures
  def extraction_payload(date: "2026-10-01", amount: 1000, merchant: "店", direction: "expense", **values)
    { "date" => date, "raw_date" => date, "date_year_explicit" => true, "amount" => amount,
      "merchant" => merchant, "direction" => direction, "transaction_kind" => "normal", "uncertain_fields" => [],
      "evidence" => { "amount" => amount.to_s, "direction" => direction, "merchant" => merchant, "transaction_kind" => "支払" } }.merge(values.stringify_keys)
  end

  def confirmed_rule(source:, category:, payment:, merchant: "店", **values)
    ImportClassificationRule.create!({ import_source: source, channel: "image", merchant_key: merchant,
      direction: category.kind, category: category, payment_method: payment, account: source.account,
      credit_card_status: source.account.credit_pending? ? "unpaid" : "not_applicable", enabled: true,
      confirmed_at: Time.current, creation_nonce: SecureRandom.uuid, creation_request_digest: "0" * 64 }.merge(values))
  end

  def import_document(account: nil, source: nil, batch_id: SecureRandom.uuid, **attributes)
    source ||= ImportSource.create!(service_key: "service-#{SecureRandom.hex(6)}", name: "取込元",
      account: account || Account.create!(name: "元口座-#{SecureRandom.hex(6)}", kind: :bank))
    ImportDocument.create!({ import_source: source, channel: "image", content_digest: Digest::SHA256.hexdigest(SecureRandom.uuid),
      batch_id: batch_id, state: "received", received_at: Time.current, fallback_date: Date.current }.merge(attributes))
  end

  def tracked_draft(**attributes)
    document = attributes.delete(:document) || import_document(account: attributes[:account], batch_id: attributes[:batch_id] || SecureRandom.uuid, state: "extracted")
    attributes[:direction] = :expense unless attributes.key?(:direction)
    attributes[:date_origin] ||= attributes[:date] ? "user" : "unresolved"
    attributes[:transaction_kind] ||= "normal"
    attributes[:confirmation_metadata] ||= { "version" => 1, "source_kind" => "normal" }
    payload = attributes.delete(:payload) || attributes.slice(:date, :amount, :direction, :memo).as_json
    external_id = attributes.delete(:trusted_external_id)
    ImportGuard.synchronize do
      Imports::EntryRecorder.call(document: document, row_number: document.import_entries.count + 1,
        payload: payload, draft_attributes: attributes, trusted_external_id: external_id).image_import_draft
    end
  end

  def review_token(entry, action, target = nil)
    ImportGuard.synchronize { Imports::ReviewToken.issue(entry: entry.reload, action: action, target_id: target&.id) }
  end
end

RSpec.configure { |config| config.include ImportFixtures }
