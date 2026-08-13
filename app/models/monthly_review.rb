class MonthlyReview < ApplicationRecord
  validates :year, presence: true, numericality: { only_integer: true }
  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :satisfaction, inclusion: { in: 1..5 }, allow_nil: true
  validates :year, uniqueness: { scope: :month }
end
