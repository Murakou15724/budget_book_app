class Setting < ApplicationRecord
  # クレカ未払い一覧で支払済にする際の引落元口座の初期値(任意)。
  # 口座がクレカ仮置きのまま支払済になっている取引を、資産スナップショットの
  # 整合性チェック(AccountReconciliation)でどの口座の残高減少として扱うかにも使う。
  belongs_to :credit_card_payment_account, class_name: "Account", optional: true

  validates :level_unit_amount, presence: true, numericality: { greater_than: 0 }
  validates :target_year, numericality: { only_integer: true }, allow_nil: true
  validates :total_savings_goal, :monthly_savings_goal, :monthly_income_estimate,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :credit_card_closing_day, :credit_card_payment_day,
            presence: true, numericality: { only_integer: true, in: 1..31 }

  def self.current
    first_or_create!
  end
end
