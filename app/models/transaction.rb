class Transaction < ApplicationRecord
  enum :entry_type, { actual: 0, planned: 1 }
  enum :direction, { income: 0, expense: 1 }
  enum :credit_card_status, { not_applicable: 0, unpaid: 1, paid: 2 }

  belongs_to :category
  belongs_to :payment_method
  belongs_to :account

  validates :date, presence: true
  validates :direction, presence: true
  validates :entry_type, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
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
end
