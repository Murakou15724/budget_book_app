class ImportEntriesController < ApplicationController
  def show
    load_entry
  end

  def preview
    ImportGuard.synchronize do
      @entry = ImportEntry.lock.find(params[:id])
      if !@entry.reference_entry_id && !@entry.terminal?
        before = Imports::Fingerprint.draft_snapshot(@entry.image_import_draft)
        @entry.image_import_draft.update!(draft_params)
        after = Imports::Fingerprint.draft_snapshot(@entry.image_import_draft)
        @entry.event!("edited", details: { "before" => before, "after" => after }) if before != after
        Imports::Matcher.classify!(@entry)
        Imports::TargetIntegrity.check!(@entry)
        @action = params[:decision].to_s
        target_id = %w[acknowledge_current acknowledge_deleted].include?(@action) ? @entry.target_transaction_id : params[:target_id]
        @target = Transaction.where(id: target_id).lock.first
        if Imports::Applier::REVIEWED_ACTIONS.include?(@action)
          @review_token = Imports::ReviewToken.issue(entry: @entry, action: @action, target_id: @target&.id)
        end
      end
    end
    load_entry
    render :show
  rescue ActiveRecord::RecordInvalid, ArgumentError
    redirect_to import_entry_path(params[:id]), alert: "入力値を確認してください。"
  end

  def resolve
    result = Imports::Applier.call(entry_id: params[:id], action: params[:decision],
      target_id: params[:target_id], review_token: params[:review_token])
    redirect_to import_entry_path(params[:id]), notice: import_result_message(result)
  end

  private

  def load_entry
    @entry = ImportEntry.find(params[:id])
    Imports::TargetIntegrity.refresh!([@entry])
    @entry.reload
    @effective = @entry.effective_entry
    @draft = @entry.image_import_draft
    @match = ImportGuard.synchronize { Imports::Matcher.call(entry: @entry, draft: @draft) }
    @events = @entry.import_events.order(id: :desc).limit(50)
    @targets = Transaction.order(date: :desc, id: :desc)
    search = params[:search].is_a?(ActionController::Parameters) ? params[:search] : ActionController::Parameters.new
    @targets = @targets.where(id: search[:id]) if search[:id].present?
    @targets = @targets.where(account_id: search[:account_id]) if search[:account_id].present?
    @targets = @targets.where(amount: search[:amount]) if search[:amount].present?
    @targets = @targets.where("date >= ?", Date.iso8601(search[:from_date])) if search[:from_date].present?
    @targets = @targets.where("date <= ?", Date.iso8601(search[:to_date])) if search[:to_date].present?
    @targets = @targets.limit(50)
  rescue Date::Error
    @targets = Transaction.none
  end

  def draft_params
    params.fetch(:draft, ActionController::Parameters.new).permit(*ImageImportDraft::EDITABLE_ATTRIBUTES)
  end

  def import_result_message(result)
    { applied: "取引を登録しました。", linked: "同一取引として対応を記録しました。", rejected: "却下を記録しました。",
      already_processed: "確定済みの結果を確認しました。", conflict: "取引との対応を再確認してください。",
      held: "保留しました。必要に応じて再プレビューしてください。", failed: "保存できませんでした。入力値と処理結果を確認してください。" }.fetch(result.status)
  end
end
