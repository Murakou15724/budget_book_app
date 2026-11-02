class ImportEvent < ApplicationRecord
  self.filter_attributes += [:details]
  belongs_to :import_document
  belongs_to :import_entry, optional: true
  validates :kind, presence: true
  before_update { throw :abort }
  before_destroy { throw :abort }
end
