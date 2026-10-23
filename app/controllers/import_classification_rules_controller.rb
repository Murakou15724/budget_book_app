class ImportClassificationRulesController < ApplicationController
  def index
    @rules = ImportClassificationRule.includes(:import_source, :category, :payment_method, :account).order(:priority, :id)
  end

  def new
    @rule = ImportClassificationRule.new(channel: "image")
    if params[:entry_id].present?
      entry = ImportEntry.find(params[:entry_id])
      @rule.assign_attributes(entry.target_snapshot.slice(*ImportClassificationRule::OUTPUT_KEYS))
      @rule.assign_attributes(import_source_id: entry.import_document.import_source_id,
        merchant_key: Imports::MerchantKey.normalize(entry.payload["merchant"]), direction: entry.payload["direction"])
    end
    @token = Imports::RuleWriter.form(entry_id: params[:entry_id])
  rescue ArgumentError => e
    redirect_to import_classification_rules_path, alert: e.message
  end

  def edit
    @rule = ImportClassificationRule.find(params[:id])
    @token = Imports::RuleWriter.form(rule: @rule)
  end

  def create
    @rule = Imports::RuleWriter.call(attributes: rule_params.to_h, token: params[:token], confirmed: params[:confirmed])
    redirect_to import_classification_rules_path, notice: "確認済みルールを保存しました。"
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => e
    render_failure(e, :new)
  end

  def update
    @rule = Imports::RuleWriter.call(attributes: rule_params.to_h, token: params[:token], confirmed: params[:confirmed], rule_id: params[:id])
    redirect_to import_classification_rules_path, notice: "ルールを更新しました。過去の実績は変更していません。"
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError => e
    render_failure(e, :edit)
  end

  private

  def rule_params
    params.require(:import_classification_rule).permit(*ImportClassificationRule::EDITABLE_ATTRIBUTES)
  end

  def render_failure(error, view)
    @rule = params[:id] ? ImportClassificationRule.find(params[:id]) : ImportClassificationRule.new
    @rule.assign_attributes(rule_params)
    @token = params[:token]
    flash.now[:alert] = error.message
    render view, status: :unprocessable_entity
  end
end
