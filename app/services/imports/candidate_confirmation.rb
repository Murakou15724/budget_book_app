module Imports
  module CandidateConfirmation
    module_function

    def apply(draft, attributes:, confirmation: {}, confirm_values: true)
      before = Fingerprint.draft_snapshot(draft)
      values = attributes.to_h.stringify_keys.slice(*ImageImportDraft::EDITABLE_ATTRIBUTES)
      old_due = draft.calculated_credit_card_payment_due_on
      supplied_due = values["credit_card_payment_due_on_override"]
      unchanged_due = draft.credit_card_payment_due_on_override.nil? && supplied_due.present? && StrictDate.parse(supplied_due) == old_due
      values["credit_card_payment_due_on_override"] = nil if unchanged_due
      %w[date credit_card_payment_due_on_override].each do |key|
        raise ArgumentError, "invalid date" if values[key].present? && !StrictDate.parse(values[key])
      end
      amount = values["amount"]
      raise ArgumentError, "invalid amount" if amount.present? && !(amount.is_a?(Integer) || /\A[1-9]\d*\z/.match?(amount.to_s))

      draft.assign_attributes(values)
      flags = confirmation.to_h.stringify_keys
      draft.date_origin = "user" if draft.date && (draft.will_save_change_to_date? || flags["date_confirmed"] == "1")
      draft.send(:clear_redundant_credit_card_payment_due_on_override)
      metadata = draft.confirmation_metadata.deep_dup
      metadata["edited_at"] = Time.current.iso8601 if before != Fingerprint.draft_snapshot(draft)
      if confirm_values
        metadata["confirmed_at"] = Time.current.iso8601
        metadata["confirmed_values"] = Fingerprint.draft_snapshot(draft)
        metadata["kind_correction"] = flags["kind_correction"] == "1"
        metadata["kind_correction_reason"] = flags["kind_correction_reason"].to_s.first(255)
      end
      draft.confirmation_metadata = metadata
      draft
    end
  end
end
