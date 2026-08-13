class AssetSnapshot < ApplicationRecord
  has_many :asset_balances, dependent: :destroy
  has_many :accounts, through: :asset_balances

  validates :recorded_on, presence: true

  def total_balance
    asset_balances.sum(:balance)
  end
end
