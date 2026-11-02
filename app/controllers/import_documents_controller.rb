class ImportDocumentsController < ApplicationController
  def index
    @page = [params[:page].to_i, 1].max
    @documents = ImportDocument.includes(import_source: :account).order(id: :desc)
    @documents = @documents.where(import_source_id: params[:source_id]) if params[:source_id].present?
    @documents = @documents.where(state: params[:state]) if %w[received failed extracted].include?(params[:state])
    @documents = @documents.where("received_at >= ?", Date.iso8601(params[:from_date])) if valid_date?(params[:from_date])
    @documents = @documents.where("received_at < ?", Date.iso8601(params[:to_date]) + 1) if valid_date?(params[:to_date])
    @documents = @documents.offset((@page - 1) * 50).limit(50)
    @documents.each { |document| Imports::TargetIntegrity.refresh_scope!(document.import_entries) }
  end

  def show
    @document = ImportDocument.includes(import_source: :account).find(params[:id])
    Imports::TargetIntegrity.refresh_scope!(@document.import_entries)
    @total_rows = @document.import_entries.count
    @total_pages = [(@total_rows + 99) / 100, 1].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    ids = @document.import_entries.order(:row_number).offset((@page - 1) * 100).limit(100).pluck(:id)
    @entries = ImportEntry.where(id: ids).includes(:image_import_draft, :reference_entry).sort_by(&:row_number)
  end

  private

  def valid_date?(value)
    value.present? && Date.iso8601(value)
  rescue ArgumentError
    false
  end
end
