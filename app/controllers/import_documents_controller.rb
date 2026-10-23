class ImportDocumentsController < ApplicationController
  def index
    @page = [params[:page].to_i, 1].max
    @documents = ImportDocument.includes(:import_events, import_source: :account, import_entries: [:image_import_draft, :reference_entry]).order(id: :desc)
    @documents = @documents.where(import_source_id: params[:source_id]) if params[:source_id].present?
    @documents = @documents.where(state: params[:state]) if %w[received failed extracted].include?(params[:state])
    @documents = @documents.where("received_at >= ?", Date.iso8601(params[:from_date])) if valid_date?(params[:from_date])
    @documents = @documents.where("received_at < ?", Date.iso8601(params[:to_date]) + 1) if valid_date?(params[:to_date])
    @documents = @documents.offset((@page - 1) * 50).limit(50)
    Imports::TargetIntegrity.refresh!(@documents.flat_map(&:import_entries))
    @documents.each { |document| document.import_entries.reset }
    ActiveRecord::Associations::Preloader.new(records: @documents, associations: { import_entries: [:image_import_draft, :reference_entry] }).call
  end

  def show
    @document = ImportDocument.includes(import_source: :account, import_entries: [:image_import_draft, :reference_entry]).find(params[:id])
    Imports::TargetIntegrity.refresh!(@document.import_entries)
    @document.reload
    ActiveRecord::Associations::Preloader.new(records: [@document], associations: { import_entries: [:image_import_draft, :reference_entry] }).call
  end

  private

  def valid_date?(value)
    value.present? && Date.iso8601(value)
  rescue ArgumentError
    false
  end
end
