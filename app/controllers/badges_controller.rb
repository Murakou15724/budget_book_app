class BadgesController < ApplicationController
  layout "workout"

  before_action :set_badge, only: [:edit, :update, :destroy]

  def index
    @badges = Badge.ordered
  end

  def new
    @badge = Badge.new
  end

  def create
    @badge = Badge.new(badge_params)

    if @badge.save
      redirect_to badges_path, notice: "称号を追加しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @badge.update(badge_params)
      redirect_to badges_path, notice: "称号を更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @badge.destroy
    redirect_to badges_path, notice: "称号を削除しました"
  end

  private

  def set_badge
    @badge = Badge.find(params[:id])
  end

  def badge_params
    params.require(:badge).permit(:required_xp, :title, :description)
  end
end
