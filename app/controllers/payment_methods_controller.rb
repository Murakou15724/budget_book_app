class PaymentMethodsController < ApplicationController
  before_action :set_payment_method, only: [:edit, :update, :destroy]

  def index
    @payment_methods = PaymentMethod.order(:position, :name)
  end

  def new
    @payment_method = PaymentMethod.new
  end

  def create
    @payment_method = PaymentMethod.new(payment_method_params)
    if @payment_method.save
      redirect_to payment_methods_path, notice: "支払方法「#{@payment_method.name}」を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @payment_method.update(payment_method_params)
      redirect_to payment_methods_path, notice: "支払方法「#{@payment_method.name}」を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @payment_method.name
    if @payment_method.destroy
      redirect_to payment_methods_path, notice: "支払方法「#{name}」を削除しました。"
    else
      redirect_to payment_methods_path, alert: @payment_method.errors.full_messages.to_sentence
    end
  end

  private

  def set_payment_method
    @payment_method = PaymentMethod.find(params[:id])
  end

  def payment_method_params
    params.require(:payment_method).permit(:name, :note, :position)
  end
end
