module Imports
  module OperationToken
    module_function

    def issue(context, purpose:)
      verifier.generate(context, expires_in: 30.minutes, purpose: purpose)
    end

    def read(token, purpose:)
      verifier.verified(token, purpose: purpose) || raise(ArgumentError, "確認期限が切れたため再プレビューしてください")
    end

    def verifier
      Rails.application.message_verifier("import_operations_v1")
    end

    def lock_entries(ids)
      documents = ImportEntry.where(id: ids).distinct.order(:import_document_id).pluck(:import_document_id)
      ImportDocument.where(id: documents).order(:id).lock.load
      entries = ImportEntry.where(id: ids).order(:id).lock.to_a
      raise ArgumentError, "対象候補がありません" unless entries.size == ids.size

      entries.each { |entry| entry.image_import_draft.lock! }
      entries
    end

    def entry_context(entry)
      { "id" => entry.id, "version" => entry.lock_version,
        "draft" => Fingerprint.digest(Fingerprint.draft_snapshot(entry.image_import_draft)),
        "metadata" => Fingerprint.digest(entry.image_import_draft.confirmation_metadata),
        "configuration" => configuration_context(entry) }
    end

    def configuration_context(entry)
      draft = entry.image_import_draft
      masters = [draft.category, draft.payment_method, draft.account, draft.to_account].map do |master|
        master && [master.id, master.updated_at&.iso8601(6)]
      end
      { "masters" => masters, "source" => entry.import_document.import_source.reload.updated_at.iso8601(6),
        "rules" => ImportClassificationRule.where(import_source_id: entry.import_document.import_source_id).order(:id).pluck(:id, :version),
        "setting" => Setting.current.reload.updated_at.iso8601(6) }
    end
  end
end
