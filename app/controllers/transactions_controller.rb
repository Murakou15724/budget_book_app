class TransactionsController < ApplicationController
  before_action :set_transaction, only: [:edit, :update, :destroy, :shift_credit_card_payment_due_on]

  # 表示期間の切り替えボタン。表示順もこの並びに従う。
  DATE_RANGES = [
    { key: "this_month", label: "今月分表示" },
    { key: "last_month", label: "先月分表示" },
    { key: "all", label: "全表示" }
  ].freeze
  helper_method :date_ranges

  def index
    @date_range_key = resolve_date_range_key
    @from_date, @to_date = date_bounds_for(@date_range_key)
    @transactions = filtered_transactions.includes(:category, :payment_method, :account).order(date: :desc, id: :desc)
    @quick_entry_templates = QuickEntryTemplate.order(:position, :name)
  end

  def new
    @transaction = Transaction.new(date: Date.current, entry_type: :actual)
    if (template = QuickEntryTemplate.find_by(id: params[:quick_entry_template_id]))
      @transaction.assign_attributes(
        direction: template.direction,
        category_id: template.category_id,
        payment_method_id: template.payment_method_id,
        account_id: template.account_id,
        to_account_id: template.to_account_id,
        credit_card_status: template.credit_card_status
      )
    end
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
    redirect_to credit_card_unpaids_path, notice: "#{updated}件の取引を支払済にしました。"
  end

  # クレカ未払い一覧から、個別の取引だけ支払予定日を1サイクル前後にずらす
  # (取込日と処理日のズレ等で、自動計算通りにならない例外に対応するため)。
  def shift_credit_card_payment_due_on
    months = params[:direction] == "prev" ? -1 : 1
    target_month = @transaction.credit_card_payment_due_on.advance(months: months).beginning_of_month
    @transaction.update!(credit_card_payment_due_on_override: Transaction.resolve_payment_due_date(target_month))
    redirect_to credit_card_unpaids_path,
                notice: "支払予定日を#{@transaction.credit_card_payment_due_on.strftime('%-m/%-d')}に変更しました。"
  end

  private

  def set_transaction
    @transaction = Transaction.find(params[:id])
  end

  def transaction_params
    params.require(:transaction).permit(
      :date, :entry_type, :direction, :category_id, :amount, :payment_method_id,
      :account_id, :to_account_id, :memo, :satisfaction, :regret, :credit_card_status,
      :credit_card_payment_due_on_override
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

  def date_ranges
    DATE_RANGES
  end

  # 期間ボタン(range)が指定されていればそれを使う。指定がなく、from_date/to_dateも
  # 両方未指定の場合(初期表示・クリア後)は「今月分表示」をデフォルトとする。
  # from_date/to_dateが手動で指定されている場合はどのボタンも選択されていない状態
  # (nil)とし、フィルタ欄で指定された範囲をそのまま使う。
  def resolve_date_range_key
    return params[:range] if date_ranges.any? { |range| range[:key] == params[:range] }
    return nil if params[:from_date].present? || params[:to_date].present?

    "this_month"
  end

  def date_bounds_for(key)
    case key
    when "this_month"
      [Date.current.beginning_of_month, Date.current.end_of_month]
    when "last_month"
      last_month = Date.current.prev_month
      [last_month.beginning_of_month, last_month.end_of_month]
    when "all"
      [nil, nil]
    else
      [parse_date_param(params[:from_date]), parse_date_param(params[:to_date])]
    end
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
