class ImageImportDraft < ApplicationRecord
  include CreditCardPaymentCycle

  enum :direction, { income: 0, expense: 1, transfer: 2, investment: 3 }
  enum :credit_card_status, { not_applicable: 0, unpaid: 1, paid: 2 }

  belongs_to :category, optional: true
  belongs_to :payment_method, optional: true
  belongs_to :account, optional: true

  validates :batch_id, presence: true

  def resolved?
    (category_id.present? || transfer? || investment?) && payment_method_id.present? && account_id.present? &&
      amount.to_i.positive?
  end
end
