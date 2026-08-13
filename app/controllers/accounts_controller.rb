class AccountsController < ApplicationController
  before_action :set_account, only: [:edit, :update, :destroy]

  def index
    @accounts = Account.order(:position, :name)
  end

  def new
    @account = Account.new
  end

  def create
    @account = Account.new(account_params)
    if @account.save
      redirect_to accounts_path, notice: "口座「#{@account.name}」を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @account.update(account_params)
      redirect_to accounts_path, notice: "口座「#{@account.name}」を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @account.name
    if @account.destroy
      redirect_to accounts_path, notice: "口座「#{name}」を削除しました。"
    else
      redirect_to accounts_path, alert: @account.errors.full_messages.to_sentence
    end
  end

  private

  def set_account
    @account = Account.find(params[:id])
  end

  def account_params
    params.require(:account).permit(:name, :kind, :position)
  end
end
