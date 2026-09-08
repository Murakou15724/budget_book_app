class WorkoutsController < ApplicationController
  layout "workout"

  def index
    setting = WorkoutSetting.current
    total_xp = WorkoutDay.total_xp

    @setting = setting
    @total_xp = total_xp
    @total_workout_count = WorkoutDay.active.count
    @current_streak = WorkoutDay.current_streak
    @longest_streak = WorkoutDay.longest_streak
    @current_badge = Badge.for_xp(total_xp)
    @next_badge = Badge.next_for_xp(total_xp)
    @current_level = Badge.level_for_xp(total_xp)

    week_range = current_week_range
    @this_week_count = WorkoutDay.active.where(date: week_range).count
    @weekly_goal_progress_rate = setting.weekly_goal_count.zero? ? 0.0 : @this_week_count.to_f / setting.weekly_goal_count

    month_range = Date.current.beginning_of_month..Date.current.end_of_month
    @this_month_xp = WorkoutDay.total_xp_in(month_range)

    @average_rpe = WorkoutEntry.where.not(rpe: nil).average(:rpe)&.round(1)
    @today_workout_day = WorkoutDay.find_by(date: Date.current)

    @recent_days_range = (13.days.ago.to_date..Date.current)
    @recent_workout_days = WorkoutDay.where(date: @recent_days_range).index_by(&:date)
  end

  private

  def current_week_range
    start_of_week = Date.current.beginning_of_week(:monday)
    start_of_week..(start_of_week + 6)
  end
end
