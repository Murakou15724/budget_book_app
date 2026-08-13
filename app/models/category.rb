class Category < ApplicationRecord
  enum :kind, { expense: 0, income: 1 }

  has_many :category_monthly_budgets, dependent: :destroy
  has_many :transactions, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :kind }
end
