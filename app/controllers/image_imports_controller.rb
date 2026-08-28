class ImageImportsController < ApplicationController
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_FILE_SIZE = 8.megabytes

  def new
  end

  def create
    image = params[:image]
    return redirect_to new_image_imports_path, alert: "画像ファイルを選択してください。" if image.blank?
    unless ALLOWED_CONTENT_TYPES.include?(image.content_type)
      return redirect_to new_image_imports_path, alert: "対応していないファイル形式です(jpeg/png/webpのみ)。"
    end
    return redirect_to new_image_imports_path, alert: "ファイルサイズが大きすぎます(8MBまで)。" if image.size > MAX_FILE_SIZE

    result = Gemini::TransactionExtractor.new(image_bytes: image.read, mime_type: image.content_type).call
    return redirect_to new_image_imports_path, alert: result.error_message unless result.success?
    return redirect_to new_image_imports_path, notice: "画像から取引を検出できませんでした。" if result.items.empty?

    batch_id, drafts = ImageImportDraftBuilder.build(result.items, manual_date: parse_manual_date)

    if Setting.current.image_import_requires_approval?
      redirect_to image_import_drafts_path(batch_id: batch_id)
    else
      applied_count, remaining_count = apply_resolved_drafts(drafts)
      notice = "#{applied_count}件を自動登録しました。"
      notice += " #{remaining_count}件は内容の確認が必要です。" if remaining_count.positive?
      redirect_to image_import_drafts_path(batch_id: batch_id), notice: notice
    end
  end

  private

  # 承認不要設定の場合、マスタ突合が完全なドラフトのみその場でTransaction化する。
  # 未解決のドラフトはレビュー画面に残し、ユーザーに確認してもらう。
  def apply_resolved_drafts(drafts)
    applied = 0
    drafts.each do |draft|
      next unless draft.resolved?

      transaction = Transaction.new(
        date: draft.date, entry_type: :actual, direction: draft.direction, category_id: draft.category_id,
        amount: draft.amount, payment_method_id: draft.payment_method_id, account_id: draft.account_id,
        memo: draft.memo, credit_card_status: draft.credit_card_status
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
