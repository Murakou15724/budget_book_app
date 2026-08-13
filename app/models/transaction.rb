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
end
