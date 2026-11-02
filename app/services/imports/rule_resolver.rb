module Imports
  module RuleResolver
    module_function

    def matches(entry)
      payload = entry.payload
      key = MerchantKey.normalize(payload["merchant"])
      return ImportClassificationRule.none unless key && %w[income expense].include?(payload["direction"]) &&
        (Array(payload["uncertain_fields"]) & %w[merchant direction]).empty?

      scope = ImportClassificationRule.where(import_source_id: entry.import_document.import_source_id,
        channel: entry.import_document.channel, merchant_key: key, direction: payload["direction"], enabled: true).order(:priority, :id)
      if entry.import_document.channel == "paypay_csv"
        resolved = SourceRoute.resolve(entry: entry)
        return ImportClassificationRule.none unless resolved.route && resolved.reasons.empty?
        scope = scope.where(import_payment_route_id: resolved.route.id)
      else
        scope = scope.where(import_payment_route_id: nil)
      end
      exact_ids = scope.select { |rule| rule.merchant_key == key }.map(&:id)
      scope.where(id: exact_ids)
    end

    def call(entry:, draft:)
      rules = matches(entry).includes(:category, :payment_method, :account, :import_source).to_a
      before = Fingerprint.draft_snapshot(draft)
      reasons = []
      reasons << "rule_missing" if rules.empty?
      reasons << "rule_ambiguous" if rules.size > 1
      if rules.one?
        rule = rules.first
        if rule.valid?
          draft.assign_attributes(rule.attributes.slice(*ImportClassificationRule::OUTPUT_KEYS))
        else
          reasons << "rule_invalid"
        end
      end
      source = entry.import_document.import_source.reload
      allowed = SourceRoute.auto_enabled?(source: source, channel: entry.import_document.channel)
      reasons << "auto_apply_disabled" unless allowed
      reasons.concat(CandidateValidator.call(draft: draft, mode: :automatic).reason_codes)
      reasons.concat(SourceRoute.reasons(entry: entry, draft: draft, mode: :automatic))
      draft.rule_decision = { "version" => 1, "evaluated_at" => Time.current.iso8601, "entry_id" => entry.id,
        "matched_rules" => rules.map(&:snapshot), "before" => before, "after" => Fingerprint.draft_snapshot(draft),
        "reason_codes" => reasons.uniq, "initial_auto_allowed" => allowed }
      draft.save!
      entry.event!("rule_evaluated", details: draft.rule_decision)
      CandidateValidator::Result.new(status: reasons.empty? ? :valid : :held, reason_codes: reasons.uniq, matched_rules: rules.map(&:snapshot))
    end

    def automatic_reasons(entry, draft)
      decision = draft.rule_decision
      reasons = CandidateValidator.call(draft: draft, mode: :automatic).reason_codes
      reasons.concat(Array(decision["reason_codes"]))
      reasons << "auto_apply_disabled" unless decision["initial_auto_allowed"] == true &&
        SourceRoute.auto_enabled?(source: entry.import_document.import_source, channel: entry.import_document.channel)
      reasons << "candidate_edited" if draft.confirmation_metadata["edited_at"].present?
      prior = Array(decision["matched_rules"])
      current = matches(entry).includes(:category, :payment_method, :account, :import_source).to_a
      reasons << "rule_changed" unless prior.one? && current.one? && current.first.valid? && current.first.snapshot == prior.first
      reasons << "rule_invalid" unless decision["after"] == Fingerprint.draft_snapshot(draft)
      reasons.concat(SourceRoute.reasons(entry: entry, draft: draft, mode: :automatic))
      reasons.uniq
    end
  end
end
