class Account < ApplicationRecord
  enum :kind, { bank: 0, e_money: 1, securities: 2, cash: 3, credit_pending: 4 }

  KIND_LABELS = {
    "bank" => "銀行",
    "e_money" => "電子マネー",
    "securities" => "証券",
    "cash" => "現金",
    "credit_pending" => "未払管理"
  }.freeze

  has_many :transactions, dependent: :restrict_with_error
  has_many :asset_balances, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true

  def kind_label
    KIND_LABELS[kind]
  end
end
