class ImportIdentity < ApplicationRecord
  belongs_to :import_source
  belongs_to :bound_entry, class_name: "ImportEntry", optional: true
  has_many :import_entries, dependent: :restrict_with_error
  validates :external_id, presence: true
  validates :external_id_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validate do
    if persisted? && (will_save_change_to_import_source_id? || will_save_change_to_external_id? || will_save_change_to_external_id_digest? ||
        (bound_entry_id_in_database.present? && will_save_change_to_bound_entry_id?))
      errors.add(:base, "外部識別子と確定済み対応は変更できません")
    end
  end
end
