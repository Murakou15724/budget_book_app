class PaymentMethod < ApplicationRecord
  has_many :transactions, dependent: :restrict_with_error
  has_many :quick_entry_templates, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end
