class CategoryMonthlyBudget < ApplicationRecord
  belongs_to :category

  validates :year, presence: true, numericality: { only_integer: true }
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :budget, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :category_id, uniqueness: { scope: [:year, :month] }
end
