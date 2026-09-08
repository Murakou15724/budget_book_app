class WorkoutSetting < ApplicationRecord
  validates :start_date, presence: true
  validates :weekly_goal_count, :weekly_goal_xp, presence: true, numericality: { only_integer: true, greater_than: 0 }

  def self.current
    first_or_create! { |s| s.start_date = Date.current }
  end
end
