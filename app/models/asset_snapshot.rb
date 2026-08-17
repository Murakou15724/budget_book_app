class AssetSnapshot < ApplicationRecord
  has_many :asset_balances, dependent: :destroy
  has_many :accounts, through: :asset_balances

  # 既存の残高(idあり)を空にする編集は、黙って無視せずバリデーションエラーとして
  # 明示させるため reject 対象にしない。reject するのは「未入力のまま追加された新規行」のみ。
  accepts_nested_attributes_for :asset_balances, reject_if: ->(attrs) { attrs["id"].blank? && attrs["balance"].blank? }

  validates :recorded_on, presence: true

  # asset_balancesがプリロード済みならSQLを発行せずメモリ上で合計する
  def total_balance
    asset_balances.sum(&:balance)
  end

  def goal_diff(savings_goal = Setting.current.total_savings_goal)
    total_balance - (savings_goal || 0)
  end
end
