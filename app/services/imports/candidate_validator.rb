module Imports
  module CandidateValidator
    Result = Struct.new(:status, :reason_codes, :before, :after, :matched_rules, keyword_init: true)
    module_function

    def call(draft:, metadata: draft.confirmation_metadata, mode: :manual)
      transaction = Transaction.new(draft.transaction_attributes)
      %i[category payment_method account to_account].each { |name| transaction.public_send("#{name}=", draft.public_send(name)) }
      reasons = transaction_reasons(transaction: transaction)
      reasons << "date_unresolved" unless %w[source user].include?(draft.date_origin) && StrictDate.parse(draft.date)
      kind = draft.transaction_kind
      confirmed = metadata["confirmed_values"] == Fingerprint.draft_snapshot(draft)
      reasons << "special_transaction" unless kind == "normal" || (%w[fee transfer investment].include?(kind) && confirmed)
      reasons << "special_transaction" if kind == "fee" && !draft.expense?
      reasons << "special_transaction" if %w[transfer investment].include?(kind) && draft.direction != kind
      reasons << "special_transaction" if (draft.transfer? || draft.investment?) && draft.direction != kind
      origin_kind = metadata["source_kind"]
      allowed_kinds = {
        "card_settlement" => %w[normal], "refund" => %w[normal], "cancellation" => %w[normal],
        "charge" => %w[normal transfer investment], "transfer" => %w[normal transfer investment],
        "fee" => %w[normal fee]
      }
      reasons << "special_transaction" if allowed_kinds.key?(origin_kind) && !allowed_kinds.fetch(origin_kind).include?(kind)
      if origin_kind.present? && origin_kind != "normal" && kind == "normal"
        reasons << "special_transaction" unless confirmed && metadata["kind_correction"] == true && metadata["kind_correction_reason"].present?
      end
      if mode.to_sym == :automatic
        reasons << "special_transaction" unless kind == "normal" && origin_kind == "normal"
        reasons.concat(evidence_reasons(metadata))
      end
      Result.new(status: reasons.empty? ? :valid : :held, reason_codes: reasons.uniq)
    end

    def evidence_reasons(metadata)
      evidence = metadata["evidence"]
      complete = metadata["version"] == 1 && evidence.is_a?(Hash) &&
        %w[amount direction transaction_kind merchant].all? { |key| evidence[key].is_a?(String) && evidence[key].present? } &&
        metadata["uncertain_fields"].is_a?(Array)
      reasons = []
      reasons << "extraction_evidence_missing" unless complete
      reasons << "extraction_uncertain" unless metadata["uncertain_fields"] == []
      reasons
    end

    def transaction_reasons(transaction:, context: :new)
      reasons = []
      reasons << "invalid_transaction" unless transaction.valid?
      amount = transaction.amount_before_type_cast
      reasons << "invalid_transaction" unless amount.is_a?(Integer) || (amount.is_a?(String) && /\A[1-9]\d*\z/.match?(amount))
      reasons << "date_unresolved" unless StrictDate.parse(transaction.date)
      category, payment, account = transaction.category, transaction.payment_method, transaction.account
      if transaction.transfer? || transaction.investment?
        expected = account&.securities? ? "bank" : account&.kind
        valid = category.nil? && transaction.to_account && transaction.to_account_id != transaction.account_id &&
          %w[bank e_money cash securities].include?(account&.kind) && %w[bank e_money cash securities].include?(transaction.to_account&.kind) &&
          %w[bank e_money cash].include?(payment&.import_kind) && payment&.import_kind == expected && transaction.not_applicable?
        reasons << "payment_route_mismatch" unless valid
      else
        reasons << "category_direction_mismatch" unless category && category.kind == transaction.direction
        if %w[unknown other].include?(payment&.import_kind) || payment.nil?
          reasons << "payment_route_unconfirmed"
        elsif payment.import_kind == "credit_card"
          valid = transaction.expense? && ((transaction.unpaid? && account&.credit_pending?) ||
            (context == :correction && transaction.paid? && account&.bank?))
          reasons << "payment_route_mismatch" unless valid
        else
          reasons << "payment_route_mismatch" unless payment.import_kind == account&.kind && transaction.not_applicable?
        end
      end
      reasons << "payment_route_mismatch" if !transaction.unpaid? && !transaction.paid? && transaction.credit_card_payment_due_on_override.present?
      reasons << "date_unresolved" if transaction.credit_card_payment_due_on_override.present? && !StrictDate.parse(transaction.credit_card_payment_due_on_override)
      reasons.uniq
    end
  end
end
