class Transaction < ApplicationRecord
  enum :entry_type, { actual: 0, planned: 1 }
  enum :direction, { income: 0, expense: 1 }
  enum :credit_card_status, { not_applicable: 0, unpaid: 1, paid: 2 }

  ENTRY_TYPE_LABELS = { "actual" => "実績", "planned" => "予定" }.freeze
  DIRECTION_LABELS = { "income" => "収入", "expense" => "支出" }.freeze
  CREDIT_CARD_STATUS_LABELS = { "not_applicable" => "対象外", "unpaid" => "未払", "paid" => "支払済" }.freeze

  belongs_to :category
  belongs_to :payment_method
  belongs_to :account

  validates :date, presence: true
  validates :date, comparison: { greater_than: Date.new(1900, 1, 1), less_than: Date.new(2100, 1, 1) }, allow_nil: true
  validates :direction, presence: true
  validates :entry_type, presence: true
  validates :amount, presence: true, numericality: { only_integer: true, greater_than: 0, less_than: 1_000_000_000 }
  validates :satisfaction, inclusion: { in: 1..5 }, allow_nil: true

  scope :in_month, ->(year, month) { where(date: Date.new(year, month, 1)..Date.new(year, month, -1)) }

  # 予算対象: 収支区分・入力区分から導出する（DBには保持しない）
  #   収入        -> :excluded（予算消費に含めない）
  #   支出・実績  -> :target
  #   支出・予定  -> :planned
  def budget_target
    return :excluded if income?

    actual? ? :target : :planned
  end

  def entry_type_label
    ENTRY_TYPE_LABELS[entry_type]
  end

  def direction_label
    DIRECTION_LABELS[direction]
  end

  def credit_card_status_label
    CREDIT_CARD_STATUS_LABELS[credit_card_status]
  end

  # 利用日(date)から、設定済みの締め日・支払日に基づいて支払予定日を算出する。
  # 締め日以前の利用は当月締め、締め日より後の利用は翌月締めとし、
  # 支払いは締め月の翌月(支払日)に行われる(例: 締め15日・支払日26日の場合、
  # 7/20の利用は8月締め→9/26払い、8/10の利用も8月締め→9/26払いとなる)。
  # 支払日が土日にあたる場合は翌平日にずらす(祝日は非対応)。
  def credit_card_payment_due_on
    setting = Setting.current
    closing_day = setting.credit_card_closing_day
    payment_day = setting.credit_card_payment_day

    closing_month = date.day <= closing_day ? date.beginning_of_month : date.next_month.beginning_of_month
    payment_month = closing_month.next_month
    last_day_of_payment_month = payment_month.end_of_month.day
    due_date = payment_month.change(day: [payment_day, last_day_of_payment_month].min)

    due_date += 1 while due_date.saturday? || due_date.sunday?
    due_date
  end
end
