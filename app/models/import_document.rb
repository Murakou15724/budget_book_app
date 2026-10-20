class ImportDocument < ApplicationRecord
  belongs_to :import_source
  has_many :import_entries, dependent: :restrict_with_error
  has_many :import_events, dependent: :restrict_with_error
  validates :channel, :batch_id, :received_at, presence: true
  validates :state, inclusion: { in: %w[received failed extracted] }
  validates :content_digest, format: { with: /\A[0-9a-f]{64}\z/ }

  def event!(kind, reason: nil, details: {})
    import_events.create!(kind: kind, reason_code: reason, details: details)
  end
end
