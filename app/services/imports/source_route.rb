module Imports
  module SourceRoute
    Resolution = Struct.new(:route, :snapshot, :reasons, :outputs, keyword_init: true)
    module_function

    def resolve(entry:)
      source = entry.import_document.import_source
      return Resolution.new(reasons: [], outputs: { "account_id" => source.account_id }) if entry.import_document.channel == "image"
      return Resolution.new(reasons: ["csv_source"], outputs: {}) unless entry.import_document.channel == "paypay_csv" && source.csv_eligible?

      method = entry.payload["source_method"].to_s
      route = source.import_payment_routes.find_by(source_method_digest: Digest::SHA256.hexdigest(method.b))
      return Resolution.new(reasons: ["csv_route_missing"], outputs: {}) unless route
      return Resolution.new(reasons: ["csv_route_collision"], outputs: {}) unless route.source_method.b == method.b

      reasons = []
      reasons << "csv_route_disabled" unless route.enabled?
      reasons << "payment_route_mismatch" unless route.valid?
      Resolution.new(route: route, snapshot: route.snapshot, reasons: reasons, outputs: route.attributes.slice(*ImportPaymentRoute::OUTPUT_KEYS))
    end

    def auto_enabled?(source:, channel:)
      return false if Setting.current.reload.image_import_requires_approval?

      case channel
      when "image" then source.reload.image_auto_apply_enabled?
      when "paypay_csv" then source.reload.csv_eligible? && source.csv_auto_apply_enabled?
      else false
      end
    end

    def reasons(entry:, draft:, mode:)
      if entry.import_document.channel == "image"
        return draft.account_id == entry.import_document.import_source.account_id || entry.import_document.import_source.legacy? ? [] : ["source_account_mismatch"]
      end
      resolved = resolve(entry: entry)
      reasons = resolved.reasons.dup
      reasons << "payment_route_mismatch" unless resolved.outputs == draft.attributes.slice(*ImportPaymentRoute::OUTPUT_KEYS)
      if mode.to_sym == :automatic
        reasons.concat(Array(entry.payload["csv_errors"]) + Array(entry.payload["csv_holds"]))
        reasons << "csv_route_changed" unless resolved.snapshot && resolved.snapshot == draft.confirmation_metadata["csv_route"]
      end
      reasons.uniq
    end
  end
end
