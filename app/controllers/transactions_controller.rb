class TransactionsController < ApplicationController
  before_action :set_transaction, only: [:edit, :update, :destroy]

  def index
    @from_date, @to_date = date_range_params
    @transactions = filtered_transactions.includes(:category, :payment_method, :account).order(date: :desc, id: :desc)
  end

  def new
    @transaction = Transaction.new(date: Date.current)
  end

  def create
    @transaction = Transaction.new(transaction_params)
    if @transaction.save
      redirect_to transactions_path, notice: "取引を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @transaction.update(transaction_params)
      redirect_to transactions_path, notice: "取引を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @transaction.destroy
      redirect_to transactions_path, notice: "取引を削除しました。"
    else
      redirect_to transactions_path, alert: @transaction.errors.full_messages.to_sentence
    end
  end

  def mark_credit_card_paid
    ids = Array(params[:transaction_ids])
    updated = Transaction.unpaid.where(id: ids)
                          .update_all(credit_card_status: Transaction.credit_card_statuses[:paid], updated_at: Time.current)
    redirect_to transactions_path(index_filter_params), notice: "#{updated}件の取引を支払済にしました。"
  end

  private

  def set_transaction
    @transaction = Transaction.find(params[:id])
  end

  def transaction_params
    params.require(:transaction).permit(
      :date, :entry_type, :direction, :category_id, :amount, :payment_method_id,
      :account_id, :memo, :satisfaction, :regret, :credit_card_status
    )
  end

  def filtered_transactions
    scope = Transaction.all
    scope = scope.where(direction: params[:direction]) if params[:direction].present?
    scope = scope.where(entry_type: params[:entry_type]) if params[:entry_type].present?
    scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
    scope = scope.where(credit_card_status: params[:credit_card_status]) if params[:credit_card_status].present?
    scope = scope.where("date >= ?", @from_date) if @from_date
    scope = scope.where("date <= ?", @to_date) if @to_date
    scope
  end

  # from_date/to_dateが両方未指定の場合(初期表示・クリア後)は今月分をデフォルト表示する。
  # どちらか一方でも指定されている場合はユーザーの意図した範囲をそのまま使う。
  def date_range_params
    return [Date.current.beginning_of_month, Date.current.end_of_month] if params[:from_date].blank? && params[:to_date].blank?

    [parse_date_param(params[:from_date]), parse_date_param(params[:to_date])]
  end

  # 不正な日付文字列(from_date/to_date)をそのままSQLに渡すとMysql2::Errorで
  # 未処理の500になるため、パース不能な値は無視する(絞り込みなし扱い)。
  def parse_date_param(value)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError
    nil
  end

  def index_filter_params
    params.permit(:direction, :entry_type, :category_id, :credit_card_status, :from_date, :to_date)
  end
  helper_method :index_filter_params
end
