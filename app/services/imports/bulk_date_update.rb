module Imports
  module BulkDateUpdate
    Result = Struct.new(:status, :entries, :before, :after, :token, :reason_codes, keyword_init: true)
    module_function

    def preview(entry_ids:, date:)
      ids = normalize_ids(entry_ids)
      value = StrictDate.parse(date) || raise(ArgumentError, "日付を確認してください")
      ImportGuard.synchronize do
        entries = OperationToken.lock_entries(ids)
        eligible!(entries)
        context = { "entries" => entries.map { |e| OperationToken.entry_context(e) }, "date" => value.iso8601, "nonce" => SecureRandom.uuid }
        Result.new(status: :preview, entries: entries, before: entries.map { |e| e.image_import_draft.date }, after: value,
          token: OperationToken.issue(context, purpose: "import_bulk_date"))
      end
    end

    def call(token:)
      context = OperationToken.read(token, purpose: "import_bulk_date")
      ImportGuard.synchronize do
        ids = context.fetch("entries").map { |e| e.fetch("id") }
        entries = OperationToken.lock_entries(ids)
        applied = entries.map { |e| e.import_events.where(kind: "date_updated").any? { |event| event.details["nonce"] == context["nonce"] } }
        return Result.new(status: :already_processed, entries: entries, after: context["date"]) if applied.all?

        eligible!(entries)
        raise ArgumentError, "候補が変更されたため再プレビューしてください" unless context["entries"] == entries.map { |e| OperationToken.entry_context(e) }

        entries.each do |entry|
          draft = entry.image_import_draft
          before = Fingerprint.draft_snapshot(draft)
          draft.date = StrictDate.parse(context["date"]) || raise(ArgumentError)
          draft.date_origin = "user"
          draft.confirmation_metadata = draft.confirmation_metadata.merge("edited_at" => Time.current.iso8601,
            "date_confirmed_at" => Time.current.iso8601)
          draft.save!
          details = { "before" => before, "after" => Fingerprint.draft_snapshot(draft), "nonce" => context["nonce"] }
          entry.event!("edited", details: details)
          entry.event!("date_updated", details: details)
        end
        entries.each { |entry| Matcher.classify!(entry) }
        Result.new(status: :updated, entries: entries, after: context["date"])
      end
    end

    def normalize_ids(values)
      ids = Array(values).map { |value| Integer(value.to_s, 10) }.uniq.sort
      raise ArgumentError, "対象は1〜100件を選択してください" unless ids.size.between?(1, 100) && ids.all?(&:positive?)

      ids
    end

    def eligible!(entries)
      raise ArgumentError, "処理済み・参照・要確認候補は一括指定できません" unless entries.all? { |e| %w[pending held].include?(e.state) && !e.reference_entry_id }
    end
  end
end
