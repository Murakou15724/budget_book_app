module Imports
  module RuleWriter
    module_function

    def form(entry_id: nil, rule: nil)
      ImportGuard.synchronize do
        context = entry_id.present? ? origin_context(entry_id) : nil
        OperationToken.issue({ "nonce" => SecureRandom.uuid, "origin" => context,
          "rule_id" => rule&.id, "rule_version" => rule&.version }, purpose: "import_rule_create")
      end
    end

    def call(attributes:, token:, confirmed:, rule_id: nil)
      raise ArgumentError, "今後再利用する内容の確認が必要です" unless confirmed == "1"

      context = OperationToken.read(token, purpose: "import_rule_create")
      raise ArgumentError unless context["rule_id"] == rule_id.presence&.to_i

      values = attributes.to_h.stringify_keys.slice(*ImportClassificationRule::EDITABLE_ATTRIBUTES)
      values["merchant_key"] = MerchantKey.normalize(values["merchant_key"])
      # フォームの文字列とDBの型を揃えて再送内容を比較する。
      typed = ImportClassificationRule.new(values).attributes.slice(*ImportClassificationRule::EDITABLE_ATTRIBUTES)
      digest = Fingerprint.digest(typed.merge("origin" => context["origin"]))
      ImportGuard.synchronize do
        unless rule_id
          existing = ImportClassificationRule.find_by(creation_nonce: context["nonce"])
          if existing
            raise ArgumentError, "同じ確認情報を異なる内容へ転用できません" unless existing.creation_request_digest == digest
            return existing
          end
        end
        if context["origin"]
          raise ArgumentError, "元実績が変更されたため再確認してください" unless origin_context(context["origin"]["entry_id"]) == context["origin"]
        end
        rule = rule_id ? ImportClassificationRule.lock.find(rule_id) : ImportClassificationRule.new
        raise ArgumentError, "ルールが変更されたため再確認してください" if rule_id && rule.version != context["rule_version"]

        rule.assign_attributes(values)
        rule.confirmed_at = Time.current
        unless rule_id
          rule.creation_nonce = context["nonce"]
          rule.creation_request_digest = digest
          rule.confirmation_entry_id = context.dig("origin", "entry_id")
        end
        rule.save!
        if rule.confirmation_entry
          rule.confirmation_entry.event!(rule_id ? "rule_changed" : "rule_created", details: { "rule" => rule.snapshot })
        end
        rule
      end
    end

    def origin_context(id)
      entry = OperationToken.lock_entries([id.to_i]).first
      draft = entry.image_import_draft
      target = Transaction.where(id: entry.target_transaction_id).lock.first
      valid = %w[applied linked].include?(entry.state) && !entry.reference_entry_id && target &&
        Fingerprint.transaction_matches?(target, entry.target_snapshot) &&
        draft.transaction_kind == "normal" && draft.confirmation_metadata["source_kind"] == "normal" &&
        MerchantKey.normalize(entry.payload["merchant"]) && (Array(entry.payload["uncertain_fields"]) & %w[merchant direction]).empty? &&
        entry.payload["direction"] == target.direction && target.account_id == entry.import_document.import_source.account_id &&
        CandidateValidator.transaction_reasons(transaction: target).empty?
      raise ArgumentError, "通常取引の確認済み履歴からだけ作成できます" unless valid

      { "entry_id" => entry.id, "version" => entry.lock_version, "snapshot" => Fingerprint.digest(Fingerprint.transaction_snapshot(target)) }
    end

    def eligible?(entry)
      ImportGuard.synchronize { origin_context(entry.id) }
      true
    rescue ArgumentError
      false
    end
  end
end
