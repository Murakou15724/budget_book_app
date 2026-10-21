class ImportSource < ApplicationRecord
  include ImportConfigurationGuard
  has_many :import_classification_rules, dependent: :restrict_with_error
  belongs_to :account, optional: true
  has_many :import_documents, dependent: :restrict_with_error
  has_many :import_identities, dependent: :restrict_with_error
  validates :service_key, format: { with: /\A[a-z0-9_.-]{1,64}\z/ }
  validates :name, presence: true
  validates :account, presence: true, unless: :legacy?
  validates :service_key, uniqueness: { scope: :account_id }
  validate :identity_is_immutable
  validate :legacy_is_reserved

  scope :available, -> { where(legacy: false) }

  private

  def identity_is_immutable
    if persisted? && (will_save_change_to_service_key? || will_save_change_to_account_id? || will_save_change_to_legacy?)
      errors.add(:base, "取込元のサービス・元口座は変更できません")
    end
  end

  def legacy_is_reserved
    errors.add(:base, "移行元は固定です") if legacy? && (service_key != "legacy_image" || account_id.present?)
    errors.add(:service_key, "は移行専用です") if !legacy? && service_key == "legacy_image"
  end
end
