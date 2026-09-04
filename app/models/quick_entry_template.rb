class QuickEntryTemplate < ApplicationRecord
  enum :direction, { income: 0, expense: 1, transfer: 2, investment: 3 }
  enum :credit_card_status, { not_applicable: 0, unpaid: 1, paid: 2 }

  belongs_to :category, optional: true
  belongs_to :payment_method
  belongs_to :account
  belongs_to :to_account, class_name: "Account", optional: true

  validates :name, presence: true, uniqueness: true
  validates :category, presence: true, unless: -> { transfer? || investment? }
  validates :credit_card_status, exclusion: { in: %w[unpaid paid], message: "はクレジットカード利用(支出)以外では設定できません" }, unless: :expense?

  def direction_label
    Transaction::DIRECTION_LABELS[direction]
  end

  def credit_card_status_label
    Transaction::CREDIT_CARD_STATUS_LABELS[credit_card_status]
  end
end
