class ImportTransactionCorrectionsController < ApplicationController
  def preview
    @result = Imports::TransactionCorrection.preview(entry_id: params[:import_entry_id],
      attributes: params.require(:transaction).permit(*Imports::TransactionCorrection::EDITABLE_ATTRIBUTES).to_h)
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => e
    redirect_to import_entry_path(params[:import_entry_id]), alert: e.message
  end

  def update
    @result = Imports::TransactionCorrection.call(entry_id: params[:import_entry_id], token: params[:token])
    redirect_to import_entry_path(params[:import_entry_id]), notice: "対応実績の訂正結果を保存しました。"
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => e
    redirect_to import_entry_path(params[:import_entry_id]), alert: e.message
  end
end
