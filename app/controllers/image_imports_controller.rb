class ImageImportsController < ApplicationController
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_FILE_SIZE = 8.megabytes

  def new
  end

  def create
    images = Array(params[:images]).select(&:present?)
    return redirect_to new_image_imports_path, alert: "画像ファイルを選択してください。" if images.empty?

    manual_date = parse_manual_date
    items = []
    errors = []

    images.each do |image|
      validation_error = validate_image(image)
      if validation_error
        errors << "#{image_label(image)}: #{validation_error}"
        next
      end

      result = Gemini::TransactionExtractor.new(image_bytes: image.read, mime_type: image.content_type).call
      if result.success?
        items.concat(result.items)
      else
        errors << "#{image_label(image)}: #{result.error_message}"
      end
    end

    if items.empty?
      return redirect_to new_image_imports_path, alert: errors.presence&.join(" / ") || "画像から取引を検出できませんでした。"
    end

    batch_id, drafts = ImageImportDraftBuilder.build(items, manual_date: manual_date)
    partial_failure_note = "(#{errors.size}枚は処理できませんでした: #{errors.join(" / ")})" if errors.any?

    if Setting.current.image_import_requires_approval?
      redirect_to image_import_drafts_path(batch_id: batch_id), notice: partial_failure_note
    else
      applied_count, remaining_count = apply_resolved_drafts(drafts)
      notice = "#{applied_count}件を自動登録しました。"
      notice += " #{remaining_count}件は内容の確認が必要です。" if remaining_count.positive?
      notice += " #{partial_failure_note}" if partial_failure_note
      redirect_to image_import_drafts_path(batch_id: batch_id), notice: notice
    end
  end

  private

  def validate_image(image)
    return "アップロードされたファイルを読み取れませんでした。" unless image.respond_to?(:content_type) && image.respond_to?(:size)
    return "対応していないファイル形式です(jpeg/png/webpのみ)。" unless ALLOWED_CONTENT_TYPES.include?(image.content_type)
    return "ファイルサイズが大きすぎます(8MBまで)。" if image.size > MAX_FILE_SIZE

    nil
  end

  # 通常のファイル選択では起きないが、不正な送信でparams[:images]の要素が
  # アップロードファイルでない(original_filenameを持たない)場合に備える。
  def image_label(image)
    image.respond_to?(:original_filename) ? image.original_filename : "(不明なファイル)"
  end

  # 承認不要設定の場合、マスタ突合が完全なドラフトのみその場でTransaction化する。
  # 未解決のドラフトはレビュー画面に残し、ユーザーに確認してもらう。
  def apply_resolved_drafts(drafts)
    applied = 0
    drafts.each do |draft|
      next unless draft.resolved?

      transaction = Transaction.new(
        date: draft.date, entry_type: :actual, direction: draft.direction, category_id: draft.category_id,
        amount: draft.amount, payment_method_id: draft.payment_method_id, account_id: draft.account_id,
        memo: draft.memo, credit_card_status: draft.credit_card_status,
        credit_card_payment_due_on_override: draft.credit_card_payment_due_on_override
      )
      if transaction.save
        draft.destroy
        applied += 1
      end
    end
    [applied, drafts.size - applied]
  end

  def parse_manual_date
    return nil if params[:manual_date].blank?

    Date.parse(params[:manual_date])
  rescue ArgumentError
    nil
  end
end
