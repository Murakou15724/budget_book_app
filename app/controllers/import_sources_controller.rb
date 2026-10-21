class ImportSourcesController < ApplicationController
  def index
    @sources = ImportSource.available.includes(:account).order(:name)
  end

  def new
    @source = ImportSource.new
  end

  def create
    @source = ImportSource.new(params.require(:import_source).permit(:name, :service_key, :account_id, :image_auto_apply_enabled))
    if @source.save
      redirect_to import_sources_path, notice: "取込元を設定しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @source = ImportSource.available.find(params[:id])
  end

  def update
    @source = ImportSource.available.find(params[:id])
    if @source.update(params.require(:import_source).permit(:name, :image_auto_apply_enabled))
      redirect_to import_sources_path, notice: "表示名を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
