require "rails_helper"

RSpec.describe WorkoutDay, type: :model do
  let!(:exercise) { Exercise.create!(name: "腕立て伏せ") }

  def create_active_day(date, xp: 50)
    day = WorkoutDay.new(date: date, status: :worked_out)
    entry = day.workout_entries.build(exercise: exercise, sets: 1, reps: 1, weight_kg: 0, duration_min: 1, rpe: 1)
    entry.xp = xp
    entry.skip_xp_calculation = true
    day.save!
    day
  end

  describe "バリデーション" do
    it "「実施」の日は種目が1件も無ければ無効" do
      day = WorkoutDay.new(date: Date.new(2026, 6, 16), status: :worked_out)

      expect(day).to be_invalid
      expect(day.errors[:base]).to be_present
    end

    it "「休み」の日は種目が無くても有効" do
      day = WorkoutDay.new(date: Date.new(2026, 6, 16), status: :rest)

      expect(day).to be_valid
    end
  end

  describe "#xp" do
    it "「実施」の日はエントリーのXP合計" do
      day = create_active_day(Date.new(2026, 6, 16), xp: 87)
      day.workout_entries.build(exercise: exercise, sets: 1, reps: 1, weight_kg: 0, duration_min: 1, rpe: 1).tap do |e|
        e.xp = 10
        e.skip_xp_calculation = true
      end
      day.save!

      expect(day.xp).to eq(97)
    end

    it "「軽め」の日は固定20XP" do
      day = WorkoutDay.create!(date: Date.new(2026, 6, 16), status: :light)

      expect(day.xp).to eq(20)
    end

    it "「休み」の日は0XP" do
      day = WorkoutDay.create!(date: Date.new(2026, 6, 16), status: :rest)

      expect(day.xp).to eq(0)
    end
  end

  describe ".current_streak" do
    it "記録が無い日は休みと同じ扱いで連続が途切れる" do
      create_active_day(Date.new(2026, 6, 16))
      create_active_day(Date.new(2026, 6, 17))
      # 6/18は記録なし
      create_active_day(Date.new(2026, 6, 19))

      expect(WorkoutDay.current_streak(as_of: Date.new(2026, 6, 19))).to eq(1)
    end

    it "今日がまだ未記録でも前日までの連続日数を返す" do
      create_active_day(Date.new(2026, 6, 16))
      create_active_day(Date.new(2026, 6, 17))

      expect(WorkoutDay.current_streak(as_of: Date.new(2026, 6, 18))).to eq(2)
    end
  end

  describe ".longest_streak" do
    it "全期間で最長の連続日数を返す" do
      create_active_day(Date.new(2026, 6, 16))
      create_active_day(Date.new(2026, 6, 17))
      create_active_day(Date.new(2026, 6, 19))
      create_active_day(Date.new(2026, 6, 20))
      create_active_day(Date.new(2026, 6, 21))

      expect(WorkoutDay.longest_streak).to eq(3)
    end
  end

  describe ".total_xp" do
    it "実施のエントリー合計と軽めの固定XPを合算する" do
      create_active_day(Date.new(2026, 6, 16), xp: 50)
      WorkoutDay.create!(date: Date.new(2026, 6, 17), status: :light)
      WorkoutDay.create!(date: Date.new(2026, 6, 18), status: :rest)

      expect(WorkoutDay.total_xp).to eq(70)
    end
  end
end
