class ImportEntry < ApplicationRecord
  TERMINAL_STATES = %w[applied linked rejected superseded deletion_acknowledged].freeze
  UNRESOLVED_STATES = %w[pending held conflict].freeze
  belongs_to :import_document
  belongs_to :import_identity, optional: true
  belongs_to :reference_entry, class_name: "ImportEntry", optional: true
  has_many :reference_entries, class_name: "ImportEntry", foreign_key: :reference_entry_id, dependent: :restrict_with_error
  has_many :bound_identities, class_name: "ImportIdentity", foreign_key: :bound_entry_id, dependent: :restrict_with_error
  has_one :image_import_draft, dependent: :restrict_with_error
  has_many :import_events, dependent: :restrict_with_error
  belongs_to :target_transaction, class_name: "Transaction", optional: true
  validates :classification, inclusion: { in: %w[new duplicate correction hold] }
  validates :state, inclusion: { in: UNRESOLVED_STATES + TERMINAL_STATES + ["reference"] }
  validates :row_number, numericality: { only_integer: true, greater_than: 0 }
  validates :payload_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validate do
    if reference_entry && (reference_entry.id == id || reference_entry.reference_entry_id.present? ||
        reference_entry.import_identity_id != import_identity_id || reference_entry.payload_digest != payload_digest)
      errors.add(:reference_entry, "は同じ外部ID・内容の代表候補を指定してください")
    end
  end

  def effective_entry
    reference_entry || self
  end

  def terminal?
    TERMINAL_STATES.include?(state)
  end

  def event!(kind, reason: nil, details: {})
    import_events.create!(import_document: import_document, kind: kind, reason_code: reason, details: details)
  end

  def summary_classification
    return classification unless reference_entry_id

    effective_entry.terminal? ? "duplicate" : "hold"
  end
end
