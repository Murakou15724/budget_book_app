class QuickEntryTemplate < ApplicationRecord
  enum :direction, { income: 0, expense: 1 }
  enum :credit_card_status, { not_applicable: 0, unpaid: 1, paid: 2 }

  belongs_to :category
  belongs_to :payment_method
  belongs_to :account

  validates :name, presence: true, uniqueness: true

  def direction_label
    Transaction::DIRECTION_LABELS[direction]
  end

  def credit_card_status_label
    Transaction::CREDIT_CARD_STATUS_LABELS[credit_card_status]
  end
end
