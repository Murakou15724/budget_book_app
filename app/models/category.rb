class Category < ApplicationRecord
  enum :kind, { expense: 0, income: 1 }

  KIND_LABELS = { "expense" => "支出", "income" => "収入" }.freeze

  has_many :category_monthly_budgets, dependent: :destroy
  has_many :transactions, dependent: :restrict_with_error
  has_many :quick_entry_templates, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :kind }

  def kind_label
    KIND_LABELS[kind]
  end
end
