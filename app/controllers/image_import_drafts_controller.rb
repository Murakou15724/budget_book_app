class ImageImportDraftsController < ApplicationController
  def index
    @documents = ImportDocument.includes(import_source: :account).order(id: :desc)
    @documents = @documents.where(batch_id: params[:batch_id]) if params[:batch_id].present?
    @documents = @documents.where(id: params[:document_ids]) if params[:document_ids].present?
    if params[:document_ids].present?
      order = Array(params[:document_ids]).map(&:to_i)
      @documents = @documents.reorder(nil).in_order_of(:id, order)
    elsif params[:batch_id].blank?
      pending_documents = @documents.where(id: ImportEntry.where(state: ImportEntry::UNRESOLVED_STATES).select(:import_document_id))
      @documents = params[:filter] == "processed" ? @documents.where.not(id: ImportEntry.where(state: ImportEntry::UNRESOLVED_STATES).select(:import_document_id)) : pending_documents
    end
    @total_documents = @documents.count
    @total_pages = [(@total_documents + 49) / 50, 1].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @documents = @documents.offset((@page - 1) * 50).limit(50)
    @documents = @documents.to_a
    @documents.each { |document| Imports::TargetIntegrity.refresh_scope!(document.import_entries) }
    scope = ImageImportDraft.pending.where(import_entries: { import_document_id: @documents.map(&:id) }).order(:id)
    @total_candidates = scope.count
    @candidate_pages = [(@total_candidates + 99) / 100, 1].max
    @candidate_page = params[:candidate_page].to_i.clamp(1, @candidate_pages)
    @drafts = scope.offset((@candidate_page - 1) * 100).limit(100).includes(:category, :payment_method, :account, :to_account).to_a
    entry_columns = ImportEntry.column_names - ["payload"]
    ActiveRecord::Associations::Preloader.new(records: @drafts, associations: :import_entry, scope: ImportEntry.select(*entry_columns)).call
    @expense_categories = Category.expense.order(:position, :name)
    @income_categories = Category.income.order(:position, :name)
    @payment_methods = PaymentMethod.order(:position, :name)
    @accounts = Account.order(:position, :name)
  end

  def bulk_approve
    ids = bulk_ids
    return head :unprocessable_entity unless ids

    results = ids.filter_map do |id|
      draft = ImageImportDraft.find_by(id: id)
      next unless draft

      attributes = params.dig(:drafts, id.to_s) || ActionController::Parameters.new
      Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve",
        attributes: attributes.permit(*ImageImportDraft::EDITABLE_ATTRIBUTES).to_h,
        confirmation: attributes.permit(:date_confirmed, :kind_correction, :kind_correction_reason).to_h)
    end
    success = results.count { |result| result.status == :applied }
    remaining = results.count { |result| %i[held conflict failed].include?(result.status) }
    redirect_to image_import_drafts_path(draft_filter_params), notice: "#{success}件を登録しました。#{remaining}件は確認・修正が必要です。"
  end

  def bulk_reject
    ids = bulk_ids
    return head :unprocessable_entity unless ids

    results = ImageImportDraft.where(id: ids).map do |draft|
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

  def bulk_ids
    values = params[:draft_ids]
    return unless values.is_a?(Array) && values.all? { |id| /\A[1-9][0-9]*\z/.match?(id.to_s) }

    ids = values.map(&:to_i).uniq
    ids if ids.size.between?(1, 100)
  end

  def draft_filter_params
    params.permit(:batch_id, :page, :candidate_page, :filter, document_ids: [], image_numbers: {}).to_h
  end
  helper_method :draft_filter_params
end
