class ImportEvent < ApplicationRecord
  belongs_to :import_document
  belongs_to :import_entry, optional: true
  validates :kind, presence: true
  before_update { throw :abort }
  before_destroy { throw :abort }
end
