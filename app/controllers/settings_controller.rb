class SettingsController < ApplicationController
  def edit
    @setting = Setting.current
  end

  def update
    @setting = Setting.current
    if @setting.update(setting_params)
      redirect_to edit_settings_path, notice: "設定を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def setting_params
    params.require(:setting).permit(:target_year, :total_savings_goal, :monthly_savings_goal, :level_unit_amount, :image_import_requires_approval)
  end
end
