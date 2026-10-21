class PaymentMethod < ApplicationRecord
  include ImportConfigurationGuard
  has_many :import_classification_rules, dependent: :restrict_with_error
  has_many :image_import_drafts, dependent: :restrict_with_error
  has_many :transactions, dependent: :restrict_with_error
  has_many :quick_entry_templates, dependent: :restrict_with_error

  IMPORT_KIND_LABELS = { "unknown" => "未設定", "cash" => "現金", "bank" => "銀行", "e_money" => "電子マネー", "credit_card" => "クレジットカード", "other" => "その他" }.freeze
  validates :import_kind, inclusion: { in: IMPORT_KIND_LABELS.keys }

  validates :name, presence: true, uniqueness: true
end
