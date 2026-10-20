module Imports
  class EntryRecorder
    class IdentityCollision < StandardError; end

    def self.call(document:, row_number:, payload:, draft_attributes:, trusted_external_id: nil)
      existing = document.import_entries.find_by(row_number: row_number)
      return existing if existing

      permitted = payload.stringify_keys.slice(*Fingerprint::PAYLOAD_KEYS)
      digest = Fingerprint.digest(Fingerprint.source_payload(permitted))
      identity = nil
      representative = nil
      unless trusted_external_id.nil?
        raise ArgumentError, "trusted_external_id must be a nonempty string" unless trusted_external_id.is_a?(String) && !trusted_external_id.empty?

        external_id = trusted_external_id.encode(Encoding::UTF_8)
        identity = ImportIdentity.find_or_create_by!(import_source: document.import_source,
          external_id_digest: Digest::SHA256.hexdigest(external_id.b)) { |i| i.external_id = external_id }
        raise IdentityCollision unless identity.external_id.b == external_id.b

        representative = identity.import_entries.where(payload_digest: digest, reference_entry_id: nil).order(:id).lock.first
      end
      entry = document.import_entries.create!(row_number: row_number, payload: permitted, payload_digest: digest,
        import_identity: identity, reference_entry: representative,
        classification: representative ? "duplicate" : "new", state: representative ? "reference" : "pending")
      ImageImportDraft.create!(draft_attributes.merge(batch_id: document.batch_id, import_entry: entry))
      entry.event!("recorded", details: { "input_kind" => document.channel })
      entry
    end
  end
end
