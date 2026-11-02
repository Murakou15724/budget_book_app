module Imports
  class CsvReceiver
    Result = Struct.new(:document, :file_error, :processing_errors, :applied_count, keyword_init: true)

    def self.call(source:, file:)
      new(source, file).call
    end

    def initialize(source, file)
      @source, @file = source, file
    end

    def call
      raise PaypayCsvParser::FileError.new(code: "csv_source") unless @source&.csv_eligible?
      raise PaypayCsvParser::FileError.new(code: "csv_file") unless @file.respond_to?(:read)
      if @file.respond_to?(:size) && @file.size > PaypayCsvParser::MAX_BYTES
        raise PaypayCsvParser::FileError.new(code: "csv_too_large")
      end
      bytes = @file.read(PaypayCsvParser::MAX_BYTES + 1) || "".b
      parsed = PaypayCsvParser.call(bytes: bytes)
      errors, applied = [], 0
      document = receive(bytes)
      fresh_entries = commit_rows(document, parsed.rows)
      fresh_entries.each do |entry|
        begin
          result = Applier.call(entry_id: entry.id, action: "auto_apply")
          applied += 1 if result.status == :applied
          if result.status == :failed
            errors << "processing_failed"
            record_failure(entry)
          end
        rescue StandardError => e
          Rails.logger.error("CsvReceiver entry_id=#{entry.id} error=#{e.class.name}")
          errors << "processing_failed"
          begin
            record_failure(entry)
          rescue ActiveRecord::ActiveRecordError
            errors << "connection_lost"
            break
          end
        end
      end
      Result.new(document: document.reload, processing_errors: errors, applied_count: applied)
    rescue PaypayCsvParser::FileError => e
      Result.new(file_error: e, processing_errors: [], applied_count: 0)
    rescue StandardError => e
      Rails.logger.error("CsvReceiver document_id=#{document&.id} error=#{e.class.name}")
      begin
        ImportGuard.synchronize do
          document.reload.lock!
          unless document.state == "extracted"
            document.update!(state: "failed", error_code: "processing_failed")
            document.event!("failed", reason: "processing_failed")
          end
        end if document&.persisted?
      rescue ActiveRecord::ActiveRecordError
        # 接続障害時は履歴を再取得できないため、呼出元に失敗を返す。
      end
      Result.new(document: document, processing_errors: ["processing_failed"], applied_count: applied || 0)
    end

    private

    def receive(bytes)
      ImportGuard.synchronize do
        document = ImportDocument.find_or_create_by!(import_source: @source, channel: "paypay_csv", content_digest: Digest::SHA256.hexdigest(bytes)) do |record|
          record.assign_attributes(batch_id: SecureRandom.uuid, state: "received", received_at: Time.current,
            byte_size: bytes.bytesize, pipeline_version: "paypay-csv-v1")
        end
        document.event!("received", details: { "input_kind" => "paypay_csv" }) if document.previously_new_record?
        document
      end
    end

    def commit_rows(document, rows)
      ImportGuard.synchronize do
        document.reload.lock!
        return [] if document.state == "extracted"

        entries = rows.map do |row|
          entry = EntryRecorder.call(document: document, row_number: row.payload.fetch("csv_row_number"),
            payload: row.payload, draft_attributes: row.draft_attributes, trusted_external_id: row.external_id)
          resolved = SourceRoute.resolve(entry: entry)
          draft = entry.image_import_draft
          draft.assign_attributes(resolved.outputs) if resolved.reasons.empty?
          draft.confirmation_metadata = draft.confirmation_metadata.merge("csv_route" => resolved.snapshot)
          draft.save!
          entry
        end
        fresh = entries.reject(&:reference_entry_id)
        fresh.each { |entry| RuleResolver.call(entry: entry, draft: entry.image_import_draft) }
        fresh.each { |entry| Matcher.classify!(entry) }
        document.update!(state: "extracted", error_code: nil)
        document.event!("extracted", details: { "row_count" => rows.size })
        fresh
      end
    end

    def record_failure(entry)
      ImportGuard.synchronize do
        entry.reload.lock!
        unless entry.terminal?
          entry.update!(state: "held", reason_code: "processing_failed")
          entry.event!("processing_failed", reason: "processing_failed")
        end
      end
    end
  end
end
