class ImportClassificationRule < ApplicationRecord
  include ImportConfigurationGuard

  OUTPUT_KEYS = %w[category_id payment_method_id account_id credit_card_status].freeze
  INPUT_KEYS = %w[import_source_id channel merchant_key direction priority enabled].freeze
  EDITABLE_ATTRIBUTES = (INPUT_KEYS + OUTPUT_KEYS).freeze
  belongs_to :import_source
  belongs_to :category
  belongs_to :payment_method
  belongs_to :account
  belongs_to :confirmation_entry, class_name: "ImportEntry", optional: true
  validates :channel, inclusion: { in: ["image"] }
  validates :direction, inclusion: { in: %w[income expense] }
  validates :credit_card_status, inclusion: { in: %w[not_applicable unpaid] }
  validates :merchant_key, :confirmed_at, :creation_nonce, :creation_request_digest, presence: true
  validates :merchant_key, length: { maximum: 255 }
  validates :priority, numericality: { only_integer: true, in: 0..9999 }
  validate :consistent_output
  before_validation { self.merchant_key = Imports::MerchantKey.normalize(merchant_key) }
  before_update { self.version += 1 }
  before_destroy { throw :abort }

  def snapshot
    attributes.slice("id", "version", *EDITABLE_ATTRIBUTES).merge("master_names" => {
      "category" => category&.name, "payment_method" => payment_method&.name, "account" => account&.name,
      "import_source" => import_source&.name })
  end

  private

  def consistent_output
    return unless import_source && category && payment_method && account

    errors.add(:account, "は元口座と一致させてください") if account_id != import_source.account_id
    projection = Transaction.new(direction: direction, category: category, payment_method: payment_method,
      account: account, credit_card_status: credit_card_status, amount: 1, date: Date.new(2026, 1, 1), entry_type: :actual)
    Imports::CandidateValidator.transaction_reasons(transaction: projection).each { |reason| errors.add(:base, reason) }
  end
end
