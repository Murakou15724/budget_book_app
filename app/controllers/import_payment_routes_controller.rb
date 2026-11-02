class ImportPaymentRoutesController < ApplicationController
  before_action :load_source

  def index
    @routes = @source.import_payment_routes.includes(:account, :payment_method).order(:id)
  end

  def new
    @route = @source.import_payment_routes.new(credit_card_status: "not_applicable")
  end

  def edit
    @route = @source.import_payment_routes.find(params[:id])
  end

  def create
    @route = @source.import_payment_routes.new(route_params)
    save_route(:new)
  end

  def update
    @route = @source.import_payment_routes.find(params[:id])
    @route.assign_attributes(route_params)
    save_route(:edit)
  end

  private

  def load_source
    @source = ImportSource.available.where(service_key: "paypay").find(params[:import_source_id])
  end

  def route_params
    params.require(:import_payment_route).permit(:source_method, :account_id, :payment_method_id, :credit_card_status, :enabled, :lock_version)
  end

  def save_route(view)
    unless params[:confirmed] == "1"
      @route.errors.add(:base, "取引方法と反映先の明示確認が必要です")
      return render view, status: :unprocessable_entity
    end
    if ImportGuard.synchronize { @route.save }
      redirect_to import_source_import_payment_routes_path(@source), notice: "支払経路を保存しました。既存候補は自動変更しません。"
    else
      render view, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique
    @route = @route.persisted? ? @source.import_payment_routes.find(@route.id) : @source.import_payment_routes.new(route_params)
    @route.errors.add(:base, "設定が変更されたか同じ取引方法が登録されています。再確認してください")
    render view, status: :unprocessable_entity
  end
end
