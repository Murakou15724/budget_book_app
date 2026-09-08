class Exercise < ApplicationRecord
  has_many :workout_entries, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end
