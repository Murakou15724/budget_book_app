module Imports
  module CsvSummary
    CATEGORIES = %w[normal automatic pending duplicate excluded error].freeze
    LABELS = { "normal" => "正常（手動反映）", "automatic" => "自動反映", "pending" => "承認待ち・要確認",
      "duplicate" => "重複・対応済み", "excluded" => "対象外・保留", "error" => "エラー" }.freeze
    module_function

    def call(document:)
      groups = CATEGORIES.to_h { |key| [key, { count: 0, outgoing: 0, incoming: 0, unknown_amount_count: 0, details: Hash.new(0) }] }
      raw = { outgoing: 0, incoming: 0, unknown_amount_count: 0 }
      ids = document.import_entries.order(:id).pluck(:id)
      ids.each_slice(100) do |batch|
        ImportEntry.where(id: batch).includes(:reference_entry, :import_events).each do |entry|
          event = entry.import_events.select { |item| item.kind == "applied" }.max_by(&:id)
          category = category(entry, event)
          group = groups.fetch(category)
          group[:count] += 1
          detail = entry.reference_entry_id ? "reference_#{entry.effective_entry.state}" : (entry.reason_code.presence || entry.state)
          group[:details][detail] += 1
          original = amounts(entry)
          add_amounts(raw, original)
          settled = if entry.state == "applied" && event
            key = event.details["direction"] == "expense" ? :outgoing : :incoming
            { key => event.details["amount"].to_i, (key == :outgoing ? :incoming : :outgoing) => 0, unknown_amount_count: 0 }
          else
            original
          end
          add_amounts(group, settled)
        end
      end
      { groups: groups, raw: raw, count: groups.values.sum { |group| group[:count] } }
    end

    def category(entry, event)
      return event&.details&.fetch("mode", nil) == "automatic" ? "automatic" : "normal" if entry.state == "applied"
      return "duplicate" if entry.state == "linked" || (entry.reference_entry_id && entry.effective_entry.terminal?)
      return "error" if !entry.terminal? && (Array(entry.payload["csv_errors"]).any? || entry.reason_code == "processing_failed")
      return "excluded" if (!entry.terminal? && Array(entry.payload["csv_holds"]).any?) || %w[rejected superseded deletion_acknowledged].include?(entry.state)

      "pending"
    end

    def amounts(entry)
      values = entry.payload.fetch("csv_amounts", {})
      foreign = Array(entry.payload["csv_holds"]).include?("csv_foreign")
      { outgoing: !foreign && values["outgoing"] ? Integer(values["outgoing"], 10) : 0,
        incoming: !foreign && values["incoming"] ? Integer(values["incoming"], 10) : 0,
        unknown_amount_count: foreign || values["outgoing"].nil? || values["incoming"].nil? ? 1 : 0 }
    end

    def add_amounts(target, amounts)
      %i[outgoing incoming unknown_amount_count].each { |key| target[key] += amounts.fetch(key, 0) }
    end
  end
end
