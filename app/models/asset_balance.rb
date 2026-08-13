class AssetBalance < ApplicationRecord
  belongs_to :asset_snapshot
  belongs_to :account

  validates :balance, presence: true, numericality: true
  validates :account_id, uniqueness: { scope: :asset_snapshot_id }
end
