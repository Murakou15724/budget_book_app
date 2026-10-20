class ImageImportDraftsController < ApplicationController
  def index
    @documents = ImportDocument.includes(import_entries: [:image_import_draft, :reference_entry], import_source: :account).order(id: :desc)
    @documents = @documents.where(batch_id: params[:batch_id]) if params[:batch_id].present?
    @documents = @documents.where(id: params[:document_ids]) if params[:document_ids].present?
    if params[:document_ids].present?
      order = Array(params[:document_ids]).map(&:to_i)
      @documents = @documents.reorder(nil).in_order_of(:id, order)
    elsif params[:batch_id].blank?
      pending_documents = @documents.where(id: ImportEntry.where(state: ImportEntry::UNRESOLVED_STATES).select(:import_document_id))
      @documents = pending_documents if pending_documents.exists?
    end
    @total_documents = @documents.count
    @total_pages = [(@total_documents + 49) / 50, 1].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @documents = @documents.offset((@page - 1) * 50).limit(50)
    Imports::TargetIntegrity.refresh!(@documents.flat_map(&:import_entries))
    @documents.each { |document| document.import_entries.reset }
    ActiveRecord::Associations::Preloader.new(records: @documents, associations: { import_entries: [:image_import_draft, :reference_entry] }).call
    @drafts = ImageImportDraft.pending.where(import_entries: { import_document_id: @documents.map(&:id) }).includes(:import_entry).order(:id)
    @expense_categories = Category.expense.order(:position, :name)
    @income_categories = Category.income.order(:position, :name)
    @payment_methods = PaymentMethod.order(:position, :name)
    @accounts = Account.order(:position, :name)
  end

  def bulk_approve
    results = Array(params[:draft_ids]).uniq.filter_map do |id|
      draft = ImageImportDraft.find_by(id: id)
      next unless draft

      attributes = params.dig(:drafts, id.to_s) || ActionController::Parameters.new
      Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve",
        attributes: attributes.permit(*ImageImportDraft::EDITABLE_ATTRIBUTES).to_h)
    end
    success = results.count { |result| result.status == :applied }
    remaining = results.count { |result| %i[held conflict failed].include?(result.status) }
    redirect_to image_import_drafts_path(draft_filter_params), notice: "#{success}件を登録しました。#{remaining}件は確認・修正が必要です。"
  end

  def bulk_reject
    results = ImageImportDraft.where(id: Array(params[:draft_ids]).uniq).map do |draft|
      Imports::Applier.call(entry_id: draft.import_entry_id, action: "reject")
    end
    rejected = results.count { |result| result.status == :rejected }
    remaining = results.count { |result| %i[held conflict failed].include?(result.status) }
    redirect_to image_import_drafts_path(draft_filter_params), notice: "#{rejected}件を却下しました。#{remaining}件は確認・修正が必要です。"
  end

  def destroy
    draft = ImageImportDraft.find(params[:id])
    Imports::Applier.call(entry_id: draft.import_entry_id, action: "reject")
    redirect_to image_import_drafts_path(draft_filter_params), notice: "候補の処理結果を記録しました。"
  end

  private

  def draft_filter_params
    params.permit(:batch_id, :page, document_ids: [], image_numbers: {}).to_h
  end
  helper_method :draft_filter_params
end
