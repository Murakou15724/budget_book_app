# 「収入見込み」(settings.monthly_income_estimateが基本値)の月別上書き。
# CategoryMonthlyBudgetと同じ役割・構造だが、単一のプランのためcategory_idを持たない。
class IncomeMonthlyEstimate < ApplicationRecord
  validates :year, presence: true, numericality: { only_integer: true }
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :year, uniqueness: { scope: :month }
end
