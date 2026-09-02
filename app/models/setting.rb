class Setting < ApplicationRecord
  validates :level_unit_amount, presence: true, numericality: { greater_than: 0 }
  validates :target_year, numericality: { only_integer: true }, allow_nil: true
  validates :total_savings_goal, :monthly_savings_goal, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :credit_card_closing_day, :credit_card_payment_day,
            presence: true, numericality: { only_integer: true, in: 1..31 }

  def self.current
    first_or_create!
  end
end
