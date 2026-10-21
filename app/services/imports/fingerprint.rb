require "digest"

module Imports
  module Fingerprint
    SOURCE_KEYS = %w[amount date occurred_at direction currency source_status merchant memo].freeze
    PAYLOAD_KEYS = (SOURCE_KEYS + %w[category_name payment_method_name account_name transaction_kind raw_date date_year_explicit uncertain_fields evidence]).freeze
    SNAPSHOT_KEYS = %w[date entry_type direction amount category_id payment_method_id account_id to_account_id memo satisfaction regret credit_card_status credit_card_payment_due_on_override credit_card_paid_on].freeze
    module_function

    def source_payload(attributes)
      values = attributes.stringify_keys
      # 欠落とnil/空文字の相違も保持する。分類推定は版判定に含めない。
      result = values.slice(*SOURCE_KEYS)
      result["amount"] = Integer(result["amount"], exception: false) || result["amount"] if result.key?("amount") && !result["amount"].nil?
      %w[date occurred_at].each do |key|
        result[key] = result[key].iso8601 if result[key].respond_to?(:iso8601)
      end
      result
    end

    def transaction_snapshot(transaction)
      SNAPSHOT_KEYS.to_h { |key| [key, transaction.public_send(key)] }.as_json.merge(
        "master_names" => %w[category payment_method account to_account].to_h { |name| [name, transaction.public_send(name)&.name] })
    end

    def transaction_matches?(transaction, snapshot)
      snapshot.present? && transaction_snapshot(transaction).slice(*SNAPSHOT_KEYS) == snapshot.slice(*SNAPSHOT_KEYS)
    end

    def draft_snapshot(draft)
      draft.attributes.slice(*ImageImportDraft::EDITABLE_ATTRIBUTES).as_json
    end

    def digest(payload)
      Digest::SHA256.hexdigest(JSON.generate(canonical(payload.as_json)))
    end

    def canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end
  end
end
