module Imports
  class ImageReceiver
    ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
    MAX_FILE_SIZE = 8.megabytes
    Result = Struct.new(:documents, :errors, :applied_count, :image_numbers, keyword_init: true)

    def self.call(source:, images:, manual_date:)
      new(source, images, manual_date).call
    end

    def initialize(source, images, manual_date)
      @source, @images, @manual_date = source, images, manual_date
      @batch_id = SecureRandom.uuid
    end

    def call
      documents, errors, applied = [], [], 0
      image_numbers = Hash.new { |hash, id| hash[id] = [] }
      @images.each_with_index do |image, index|
        error = validation_error(image)
        if error
          errors << "画像#{index + 1}: #{error}"
          next
        end
        bytes = image.read
        document = receive(bytes, image)
        documents << document
        image_numbers[document.id.to_s] << index + 1
        next if document.state == "extracted"

        begin
          response = Gemini::TransactionExtractor.new(image_bytes: bytes, mime_type: image.content_type).call
          unless response.success?
            fail_document(document, "extraction_failed")
            errors << "画像#{index + 1}: 解析に失敗しました。再アップロードで再試行できます。"
            next
          end
          fresh_entries = commit_extraction(document, response.items)
          unless Setting.current.image_import_requires_approval?
            fresh_entries.each do |entry|
              result = Applier.call(entry_id: entry.id, action: "approve")
              applied += 1 if result.status == :applied
            end
          end
        rescue StandardError => e
          Rails.logger.error("ImageReceiver failed: #{e.class.name}")
          fail_document(document, "processing_failed")
          errors << "画像#{index + 1}: 処理に失敗しました。履歴を確認してください。"
        end
      end
      Result.new(documents: documents.uniq(&:id).map(&:reload), errors: errors, applied_count: applied, image_numbers: image_numbers)
    end

    private

    def validation_error(image)
      return "アップロードされたファイルを読み取れませんでした。" unless image.respond_to?(:content_type) && image.respond_to?(:size) && image.respond_to?(:read)
      return "対応していないファイル形式です(jpeg/png/webpのみ)。" unless ALLOWED_CONTENT_TYPES.include?(image.content_type)
      return "ファイルサイズが大きすぎます(8MBまで)。" if image.size > MAX_FILE_SIZE
    end

    def receive(bytes, image)
      ImportGuard.synchronize do
        document = ImportDocument.find_or_create_by!(import_source: @source, channel: "image", content_digest: Digest::SHA256.hexdigest(bytes)) do |d|
          d.assign_attributes(batch_id: @batch_id, state: "received", received_at: Time.current,
            manual_date: @manual_date, fallback_date: Date.current, mime_type: image.content_type,
            byte_size: bytes.bytesize, pipeline_version: "image-v1")
        end
        document.event!("received", details: { "input_kind" => "image" }) if document.previously_new_record?
        document
      end
    end

    def commit_extraction(document, items)
      ImportGuard.synchronize do
        document.lock!
        return [] if document.state == "extracted"

        _, drafts = ImageImportDraftBuilder.build(items, document: document)
        document.update!(state: "extracted", error_code: nil)
        document.event!("extracted", details: { "row_count" => drafts.size })
        drafts.map(&:import_entry)
      end
    end

    def fail_document(document, code)
      ImportGuard.synchronize do
        document.reload.lock!
        unless document.state == "extracted"
          document.update!(state: "failed", error_code: code)
          document.event!("failed", reason: code)
        end
      end
    end
  end
end
