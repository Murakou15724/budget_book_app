class ImageImportsController < ApplicationController
  def new
    @sources = ImportSource.available.includes(:account).order(:name)
  end

  def create
    if params[:manual_date].present?
      @sources = ImportSource.available.includes(:account).order(:name)
      flash.now[:alert] = "日付の一括指定は抽出後に対象と結果を確認して行ってください。"
      return render :new, status: :unprocessable_entity
    end
    images = Array(params[:images]).select(&:present?)
    return redirect_to new_image_imports_path, alert: "画像ファイルを選択してください。" if images.empty?

    source = ImportSource.available.find_by(id: params[:import_source_id])
    return redirect_to new_image_imports_path, alert: "取込元を選択してください。" unless source

    result = Imports::ImageReceiver.call(source: source, images: images, manual_date: nil)
    if result.documents.empty?
      redirect_to new_image_imports_path, alert: result.errors.join(" / ")
    else
      notice = "#{result.applied_count}件を自動登録しました。"
      notice += " #{result.errors.size}枚は処理できませんでした。#{result.errors.join(' / ')}" if result.errors.any?
      redirect_to image_import_drafts_path(document_ids: result.documents.map(&:id), image_numbers: result.image_numbers), notice: notice
    end
  end

end
