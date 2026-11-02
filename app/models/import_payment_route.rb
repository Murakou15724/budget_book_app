require "digest"

class ImportPaymentRoute < ApplicationRecord
  include ImportConfigurationGuard

  OUTPUT_KEYS = %w[account_id payment_method_id credit_card_status].freeze
  belongs_to :import_source, inverse_of: :import_payment_routes
  belongs_to :account, inverse_of: :import_payment_routes
  belongs_to :payment_method, inverse_of: :import_payment_routes
  has_many :import_classification_rules, inverse_of: :import_payment_route, dependent: :restrict_with_error
  self.filter_attributes += [:source_method]
  validates :source_method, :source_method_digest, :credit_card_status, presence: true
  validates :source_method, length: { maximum: 255 }
  validates :source_method_digest, uniqueness: { scope: :import_source_id }, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :credit_card_status, inclusion: { in: %w[not_applicable unpaid] }
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :enabled, inclusion: { in: [true, false] }
  before_validation { self.source_method_digest = Digest::SHA256.hexdigest(source_method.to_s.b) }
  before_update { self.version += 1 }
  before_destroy { errors.add(:base, "支払経路は削除できません。停止してください"); throw :abort }
  validate :valid_route

  def self.mixed_method?(value)
    value.match?(/併用|[+＋&＆\/／]|、|,/)
  end

  def snapshot
    attributes.slice("id", "version", "enabled", "source_method", *OUTPUT_KEYS).merge(
      "masters" => [account, payment_method].map { |master| master && [master.id, master.updated_at&.iso8601(6)] })
  end

  private

  def valid_route
    errors.add(:import_source, "はPayPayの取込元を選択してください") unless import_source&.csv_eligible?
    if persisted? && (will_save_change_to_source_method? || will_save_change_to_import_source_id? || will_save_change_to_source_method_digest?)
      errors.add(:base, "取込元と取引方法は変更できません")
    end
    errors.add(:source_method, "に制御文字は使えません") if source_method.to_s.match?(/[[:cntrl:]]/)
    errors.add(:source_method, "はポイント・混合経路を指定できません") if source_method.to_s.include?("ポイント") || self.class.mixed_method?(source_method.to_s)
    return unless account && payment_method

    valid = if payment_method.import_kind == "credit_card"
      account.credit_pending? && credit_card_status == "unpaid"
    else
      %w[bank cash e_money].include?(payment_method.import_kind) && payment_method.import_kind == account.kind && credit_card_status == "not_applicable"
    end
    errors.add(:base, "支払方法・口座・クレカ状態が一致しません") unless valid
  end
end
