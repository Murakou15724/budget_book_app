class WeeklyReview < ApplicationRecord
  validates :week_start_date, presence: true, uniqueness: true

  # 実施回数・合計XPなどはworkout_daysから都度算出する(二重管理を避けるため)。
  def date_range
    week_start_date...(week_start_date + 7)
  end

  def workout_count
    WorkoutDay.active.where(date: date_range).count
  end

  def total_xp
    WorkoutDay.total_xp_in(date_range)
  end

  def total_duration_min
    WorkoutEntry.joins(:workout_day).where(workout_days: { date: date_range }).sum(:duration_min)
  end

  def average_rpe
    WorkoutEntry.joins(:workout_day).where(workout_days: { date: date_range }).where.not(rpe: nil).average(:rpe)
  end
end
