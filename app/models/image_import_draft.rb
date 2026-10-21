class ImageImportDraft < ApplicationRecord
  include CreditCardPaymentCycle

  EDITABLE_ATTRIBUTES = %w[date direction amount memo category_id payment_method_id account_id credit_card_status credit_card_payment_due_on_override transaction_kind to_account_id].freeze
  belongs_to :import_entry
  scope :pending, -> { joins(:import_entry).where(import_entries: { state: ImportEntry::UNRESOLVED_STATES }) }

  def transaction_attributes
    attributes.slice(*(EDITABLE_ATTRIBUTES - ["transaction_kind"])).merge("direction" => direction, "credit_card_status" => credit_card_status, "entry_type" => "actual")
  end

  enum :direction, { income: 0, expense: 1, transfer: 2, investment: 3 }
  enum :credit_card_status, { not_applicable: 0, unpaid: 1, paid: 2 }

  belongs_to :to_account, class_name: "Account", optional: true
  after_initialize do
    self.confirmation_metadata ||= {}
    self.rule_decision ||= {}
  end
  validates :date_origin, inclusion: { in: %w[unresolved source user] }
  validates :transaction_kind, inclusion: { in: (Imports::TransactionKindClassifier::KINDS + ["investment"]) }

  belongs_to :category, optional: true
  belongs_to :payment_method, optional: true
  belongs_to :account, optional: true

  validates :batch_id, presence: true
  validates :memo, :suggested_category_name, :suggested_payment_method_name, :suggested_account_name, length: { maximum: 255 }
  validates :amount, numericality: { only_integer: true, greater_than_or_equal_to: -2**31, less_than: 2**31 }, allow_nil: true
  validate :referenced_masters_exist

  def resolved?
    Imports::CandidateValidator.call(draft: self).status == :valid
  end

  private

  def referenced_masters_exist
    %i[category payment_method account to_account].each do |name|
      errors.add(name, "を選び直してください") if public_send("#{name}_id").present? && public_send(name).nil?
    end
  end
end
