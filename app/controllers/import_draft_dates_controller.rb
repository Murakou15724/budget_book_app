class ImportDraftDatesController < ApplicationController
  def preview
    @result = Imports::BulkDateUpdate.preview(entry_ids: params[:entry_ids], date: params[:date])
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => e
    @error = e.message
    render :error, status: :unprocessable_entity
  end

  def update
    @result = Imports::BulkDateUpdate.call(token: params[:token])
    render :preview
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => e
    redirect_to image_import_drafts_path, alert: e.message
  end
end
