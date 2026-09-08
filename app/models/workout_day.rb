class WorkoutDay < ApplicationRecord
  LIGHT_XP = 20

  enum :status, { worked_out: 0, light: 1, rest: 2 }

  STATUS_LABELS = { "worked_out" => "実施", "light" => "軽め", "rest" => "休み" }.freeze

  has_many :workout_entries, dependent: :destroy
  accepts_nested_attributes_for :workout_entries, allow_destroy: true, reject_if: :all_blank

  validates :date, presence: true, uniqueness: true
  validate :worked_out_requires_at_least_one_entry

  scope :active, -> { where(status: [:worked_out, :light]) }

  def status_label
    STATUS_LABELS[status]
  end

  def xp
    case status
    when "worked_out" then workout_entries.sum(&:xp)
    when "light" then LIGHT_XP
    else 0
    end
  end

  # 記録がない日は「休み」と同じ扱いにするため、行の有無に関わらず判定できるようにする。
  def self.active_on?(date)
    active.exists?(date: date)
  end

  # 今日はまだ記録していない可能性があるため、今日が未記録なら前日から遡って数える。
  def self.current_streak(as_of: Date.current)
    date = as_of
    date -= 1 unless active_on?(date)

    streak = 0
    while active_on?(date)
      streak += 1
      date -= 1
    end
    streak
  end

  def self.longest_streak
    dates = active.order(:date).pluck(:date)
    return 0 if dates.empty?

    longest = current = 1
    dates.each_cons(2) do |prev, cur|
      current = (cur == prev + 1) ? current + 1 : 1
      longest = [longest, current].max
    end
    longest
  end

  def self.total_xp
    worked_out_xp = joins(:workout_entries).where(status: :worked_out).sum("workout_entries.xp")
    worked_out_xp + light.count * LIGHT_XP
  end

  def self.total_xp_in(range)
    worked_out_xp = joins(:workout_entries).where(status: :worked_out, date: range).sum("workout_entries.xp")
    worked_out_xp + light.where(date: range).count * LIGHT_XP
  end

  private

  def worked_out_requires_at_least_one_entry
    return unless worked_out?
    return if workout_entries.reject(&:marked_for_destruction?).any?

    errors.add(:base, "「実施」の日は種目を1つ以上入力してください")
  end
end
