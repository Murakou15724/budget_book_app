class CsvImportsController < ApplicationController
  def new
    @sources = ImportSource.available.where(service_key: "paypay").order(:name)
  end

  def create
    new
    source = @sources.find_by(id: params[:source_id])
    @result = Imports::CsvReceiver.call(source: source, file: params[:csv_file])
    if @result.file_error
      @error = helpers.import_reason_label(@result.file_error.code)
      @error += " / 論理行 #{@result.file_error.row_number}" if @result.file_error.row_number
      @error += " / parser行 #{@result.file_error.physical_line}" if @result.file_error.physical_line
      render :new, status: :unprocessable_entity
    elsif @result.document
      redirect_to import_document_path(@result.document), notice: "今回新たに自動反映した取引は#{@result.applied_count}件です。表示は文書の累積結果です。",
        alert: @result.processing_errors.any? ? "処理に失敗した行があります。履歴と未処理候補を確認してください。" : nil
    else
      @error = "保存できませんでした。履歴を確認し、再送してください。"
      render :new, status: :unprocessable_entity
    end
  end
end
