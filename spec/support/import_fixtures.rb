module ImportFixtures
  def import_document(account: nil, source: nil, batch_id: SecureRandom.uuid, **attributes)
    source ||= ImportSource.create!(service_key: "service-#{SecureRandom.hex(6)}", name: "取込元",
      account: account || Account.create!(name: "元口座-#{SecureRandom.hex(6)}", kind: :bank))
    ImportDocument.create!({ import_source: source, channel: "image", content_digest: Digest::SHA256.hexdigest(SecureRandom.uuid),
      batch_id: batch_id, state: "received", received_at: Time.current, fallback_date: Date.current }.merge(attributes))
  end

  def tracked_draft(**attributes)
    document = attributes.delete(:document) || import_document(account: attributes[:account], batch_id: attributes[:batch_id] || SecureRandom.uuid, state: "extracted")
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
