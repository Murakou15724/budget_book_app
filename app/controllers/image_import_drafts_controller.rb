class ImageImportDraftsController < ApplicationController
  before_action :set_draft, only: [:destroy]

  def index
    @drafts = if params[:batch_id].present?
                ImageImportDraft.where(batch_id: params[:batch_id]).order(:id)
              else
                ImageImportDraft.order(:id)
              end
    @expense_categories = Category.expense.order(:position, :name)
    @income_categories = Category.income.order(:position, :name)
    @payment_methods = PaymentMethod.order(:position, :name)
    @accounts = Account.order(:position, :name)
  end

  def bulk_approve
    ids = Array(params[:draft_ids])
    errors = []

    ids.each do |id|
      draft = ImageImportDraft.find_by(id: id)
      next unless draft

      attrs = params.dig(:drafts, id.to_s) || ActionController::Parameters.new
      draft.assign_attributes(attrs.permit(
        :date, :direction, :amount, :memo, :category_id, :payment_method_id, :account_id,
        :credit_card_status, :credit_card_payment_due_on_override
      ))

      transaction = Transaction.new(
        date: draft.date, entry_type: :actual, direction: draft.direction, category_id: draft.category_id,
        amount: draft.amount, payment_method_id: draft.payment_method_id, account_id: draft.account_id,
        memo: draft.memo, credit_card_status: draft.credit_card_status,
        credit_card_payment_due_on_override: draft.credit_card_payment_due_on_override
      )
      if transaction.save
        draft.destroy
      else
        draft.save
        errors << "#{draft.memo.presence || '取引'}: #{transaction.errors.full_messages.to_sentence}"
      end
    end

    if errors.any?
      redirect_to image_import_drafts_path(batch_id: params[:batch_id]), alert: errors.join(" / ")
    else
      redirect_to image_import_drafts_path(batch_id: params[:batch_id]), notice: "選択した候補を取引として登録しました。"
    end
  end

  def bulk_reject
    ImageImportDraft.where(id: Array(params[:draft_ids])).destroy_all
    redirect_to image_import_drafts_path(batch_id: params[:batch_id]), notice: "選択した候補を却下しました。"
  end

  def destroy
    @draft.destroy
    redirect_to image_import_drafts_path(batch_id: params[:batch_id]), notice: "候補を却下しました。"
  end

  private

  def set_draft
    @draft = ImageImportDraft.find(params[:id])
  end
end
