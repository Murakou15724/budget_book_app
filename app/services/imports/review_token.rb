module Imports
  module ReviewToken
    module_function

    def issue(entry:, action:, target_id: nil)
      verifier.generate(context(entry, action, target_id), expires_in: 30.minutes, purpose: "import_review")
    end

    def valid?(token, entry:, action:, target_id: nil)
      verified = verifier.verified(token, purpose: "import_review")
      verified && verified == context(entry, action, target_id)
    end

    def context(entry, action, target_id)
      match = Matcher.call(entry: entry, draft: entry.image_import_draft)
      target_id = entry.target_transaction_id if %w[acknowledge_current acknowledge_deleted].include?(action.to_s)
      target = Transaction.where(id: target_id).lock.first if target_id.present?
      versions = entry.import_identity&.import_entries&.order(:id)&.lock&.map { |e| [e.id, e.lock_version] }
      { "entry_id" => entry.id, "lock_version" => entry.lock_version,
        "source_account" => entry.import_document.import_source.account_id,
        "source_account_mismatch" => entry.image_import_draft.account_id != entry.import_document.import_source.account_id,
        "masters" => [entry.image_import_draft.category&.kind, entry.image_import_draft.payment_method&.import_kind, entry.image_import_draft.account&.kind],
        "metadata" => Fingerprint.digest(entry.image_import_draft.confirmation_metadata),
        "draft" => Fingerprint.digest(Fingerprint.draft_snapshot(entry.image_import_draft)),
        "transactions" => match.transactions.map { |t| [t.id, Fingerprint.digest(Fingerprint.transaction_snapshot(t))] },
        "drafts" => match.drafts.map { |d| [d.import_entry_id, Fingerprint.digest(Fingerprint.draft_snapshot(d))] },
        "versions" => versions, "action" => action.to_s, "target_id" => target_id.presence&.to_i,
        "target" => target && Fingerprint.digest(Fingerprint.transaction_snapshot(target)) }
        .merge("configuration" => OperationToken.configuration_context(entry),
          "target_masters" => target && [target.category&.kind, target.payment_method&.import_kind, target.account&.kind, target.to_account&.kind])
    end

    def verifier
      Rails.application.message_verifier("import_review_v1")
    end
  end
end
