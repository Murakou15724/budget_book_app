module Imports
  module TransactionCorrection
    Result = Struct.new(:status, :entry, :before, :after, :related_entries, :token, :reason_codes, keyword_init: true)
    EDITABLE_ATTRIBUTES = %w[date direction amount category_id payment_method_id account_id to_account_id memo credit_card_status credit_card_payment_due_on_override].freeze
    module_function

    def preview(entry_id:, attributes:)
      ImportGuard.synchronize do
        entry, target, related = load_target(entry_id)
        projection = project(target, attributes)
        before = Fingerprint.transaction_snapshot(target)
        after = Fingerprint.transaction_snapshot(projection)
        context = { "entry_id" => entry.id, "target_id" => target.id, "before" => before, "after" => after,
          "related" => related.map { |e| [e.id, e.lock_version] }, "settings" => settings_context,
          "configuration" => configuration_context(related, target),
          "attributes" => attributes.to_h.stringify_keys.slice(*EDITABLE_ATTRIBUTES), "nonce" => SecureRandom.uuid }
        Result.new(status: :preview, entry: entry, before: before, after: after, related_entries: related,
          token: OperationToken.issue(context, purpose: "import_correction"))
      end
    end

    def call(entry_id:, token:)
      context = OperationToken.read(token, purpose: "import_correction")
      raise ArgumentError unless context["entry_id"] == entry_id.to_i

      ImportGuard.synchronize do
        entry = ImportEntry.find(entry_id)
        if entry.import_events.where(kind: "transaction_corrected").any? { |event| event.details["nonce"] == context["nonce"] }
          return Result.new(status: :already_processed, entry: entry)
        end
        entry, target, related = load_target(entry_id)
        valid = context["target_id"] == target.id && context["before"] == Fingerprint.transaction_snapshot(target) &&
          context["related"] == related.map { |e| [e.id, e.lock_version] } && context["settings"] == settings_context &&
          context["configuration"] == configuration_context(related, target)
        raise ArgumentError, "対象や設定が変更されたため再プレビューしてください" unless valid

        projection = project(target, context["attributes"])
        raise ArgumentError, "計算結果が変わりました" unless context["after"] == Fingerprint.transaction_snapshot(projection)

        state = entry.state
        target.update!(context["attributes"])
        raise ArgumentError, "保存結果がプレビューと一致しません" unless Fingerprint.transaction_snapshot(target) == context["after"]

        entry.reload.update!(state: state, target_snapshot: context["after"], reason_code: "correction_confirmed")
        entry.event!("transaction_corrected", details: context.slice("before", "after", "nonce", "target_id", "related"))
        Result.new(status: :updated, entry: entry, before: context["before"], after: context["after"], related_entries: related)
      end
    end

    def load_target(entry_id)
      entry = ImportEntry.find(entry_id)
      related_ids = ImportEntry.where(target_transaction_id: entry.target_transaction_id).order(:id).pluck(:id)
      related = OperationToken.lock_entries(related_ids)
      entry = related.find { |e| e.id == entry_id.to_i }
      raise ArgumentError, "反映済み候補から実行してください" unless entry && %w[applied linked].include?(entry.state) && !entry.reference_entry_id

      target = Transaction.where(id: entry.target_transaction_id).lock.first
      raise ArgumentError, "対応実績が削除または変更されています" unless target && Fingerprint.transaction_matches?(target, entry.target_snapshot)

      [entry, target, related]
    end

    def project(target, attributes)
      values = attributes.to_h.stringify_keys.slice(*EDITABLE_ATTRIBUTES)
      %w[date credit_card_payment_due_on_override].each do |key|
        raise ArgumentError, "日付を確認してください" if values[key].present? && !StrictDate.parse(values[key])
      end
      projection = target.dup
      projection.clear_changes_information
      projection.assign_attributes(values)
      reasons = CandidateValidator.transaction_reasons(transaction: projection, context: :correction)
      raise ArgumentError, reasons.join(", ") unless reasons.empty?

      projection.normalize_import_payment_values
      projection
    end

    def settings_context
      Setting.current.reload.attributes.slice("credit_card_closing_day", "credit_card_payment_day")
    end

    def configuration_context(related, target)
      { "entries" => related.map { |entry| [entry.id, OperationToken.configuration_context(entry)] },
        "target_masters" => [target.category, target.payment_method, target.account, target.to_account].map { |master| master && [master.id, master.updated_at.iso8601(6)] } }
    end
  end
end
