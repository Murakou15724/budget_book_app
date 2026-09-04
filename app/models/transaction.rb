class Transaction < ApplicationRecord
  include CreditCardPaymentCycle

  enum :entry_type, { actual: 0, planned: 1 }
  # 収入/支出に加え、振替(transfer)・投資(investment)を区別する。
  # 振替・投資は「消費」ではなく資金の置き場所が変わるだけの取引のため、
  # 支出集計(MonthlySummary/CategoryExpenseSummary)には含めない。
  enum :direction, { income: 0, expense: 1, transfer: 2, investment: 3 }
  enum :credit_card_status, { not_applicable: 0, unpaid: 1, paid: 2 }

  ENTRY_TYPE_LABELS = { "actual" => "実績", "planned" => "予定" }.freeze
  DIRECTION_LABELS = { "income" => "収入", "expense" => "支出", "transfer" => "振替", "investment" => "投資" }.freeze
  CREDIT_CARD_STATUS_LABELS = { "not_applicable" => "対象外", "unpaid" => "未払", "paid" => "支払済" }.freeze

  belongs_to :category, optional: true
  belongs_to :payment_method
  belongs_to :account
  # 振替・投資の移動先口座(任意)。資産スナップショットとの整合性チェックにのみ使う。
  belongs_to :to_account, class_name: "Account", optional: true

  validates :date, presence: true
  validates :date, comparison: { greater_than: Date.new(1900, 1, 1), less_than: Date.new(2100, 1, 1) }, allow_nil: true
  validates :direction, presence: true
  validates :entry_type, presence: true
  validates :amount, presence: true, numericality: { only_integer: true, greater_than: 0, less_than: 1_000_000_000 }
  validates :satisfaction, inclusion: { in: 1..5 }, allow_nil: true
  # 振替・投資はカテゴリ分類になじまないため、収入・支出のみ必須にする。
  validates :category, presence: true, unless: -> { transfer? || investment? }
  validates :credit_card_status, exclusion: { in: %w[unpaid paid], message: "はクレジットカード利用(支出)以外では設定できません" }, unless: :expense?
  validate :to_account_must_differ_from_account

  scope :in_month, ->(year, month) { where(date: Date.new(year, month, 1)..Date.new(year, month, -1)) }

  # 予算対象: 収支区分・入力区分から導出する（DBには保持しない）
  #   収入・振替・投資 -> :excluded（予算消費に含めない）
  #   支出・実績       -> :target
  #   支出・予定       -> :planned
  def budget_target
    return :excluded if income? || transfer? || investment?

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

  # 未払いのクレカ取引を支払予定日ごとにグルーピングする(支払日の昇順)。
  # クレカ未払い一覧・ダッシュボードの「次回支払い」表示で共用する。
  def self.unpaid_grouped_by_payment_due_date
    unpaid.includes(:category, :payment_method, :account)
          .order(date: :asc, id: :asc)
          .group_by(&:credit_card_payment_due_on)
          .sort
          .to_h
  end

  private

  def to_account_must_differ_from_account
    return if to_account_id.blank? || to_account_id != account_id

    errors.add(:to_account, "は口座・置き場所と異なる口座を選択してください")
  end
end
