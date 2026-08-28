class QuickEntryTemplatesController < ApplicationController
  before_action :set_quick_entry_template, only: [:edit, :update, :destroy]

  def index
    @quick_entry_templates = QuickEntryTemplate.order(:position, :name)
  end

  def new
    @quick_entry_template = QuickEntryTemplate.new
  end

  def create
    @quick_entry_template = QuickEntryTemplate.new(quick_entry_template_params)
    if @quick_entry_template.save
      redirect_to quick_entry_templates_path, notice: "クイック入力テンプレート「#{@quick_entry_template.name}」を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @quick_entry_template.update(quick_entry_template_params)
      redirect_to quick_entry_templates_path, notice: "クイック入力テンプレート「#{@quick_entry_template.name}」を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @quick_entry_template.name
    if @quick_entry_template.destroy
      redirect_to quick_entry_templates_path, notice: "クイック入力テンプレート「#{name}」を削除しました。"
    else
      redirect_to quick_entry_templates_path, alert: @quick_entry_template.errors.full_messages.to_sentence
    end
  end

  private

  def set_quick_entry_template
    @quick_entry_template = QuickEntryTemplate.find(params[:id])
  end

  def quick_entry_template_params
    params.require(:quick_entry_template).permit(
      :name, :direction, :category_id, :payment_method_id, :account_id, :credit_card_status, :position
    )
  end
end
