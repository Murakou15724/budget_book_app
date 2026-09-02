class ImageImportDraft < ApplicationRecord
  include CreditCardPaymentCycle

  enum :direction, { income: 0, expense: 1 }
  enum :credit_card_status, { not_applicable: 0, unpaid: 1, paid: 2 }

  belongs_to :category, optional: true
  belongs_to :payment_method, optional: true
  belongs_to :account, optional: true

  validates :batch_id, presence: true

  def resolved?
    category_id.present? && payment_method_id.present? && account_id.present?
  end
end
