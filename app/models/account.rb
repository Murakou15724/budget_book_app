class Account < ApplicationRecord
  enum :kind, { bank: 0, e_money: 1, securities: 2, cash: 3, credit_pending: 4 }

  has_many :transactions, dependent: :restrict_with_error
  has_many :asset_balances, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end
