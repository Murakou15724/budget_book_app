require "rails_helper"

RSpec.describe WorkoutEntry, type: :model do
  let!(:exercise) { Exercise.create!(name: "腕立て伏せ") }
  let!(:workout_day) { WorkoutDay.new(date: Date.new(2026, 6, 16), status: :worked_out) }

  describe ".calculate_xp" do
    it "Excelの数式(セット*回数*MAX(重量,1)/20 + 時間*2 + RPE*5)通りに算出する" do
      xp = WorkoutEntry.calculate_xp(sets: 4, reps: 10, weight_kg: 0, duration_min: 30, rpe: 5)

      expect(xp).to eq(87)
    end

    it "重量0はMAX(重量,1)により1として扱う" do
      xp = WorkoutEntry.calculate_xp(sets: 2, reps: 180, weight_kg: 0, duration_min: 15, rpe: 5)

      expect(xp).to eq(73)
    end
  end

  it "保存時にXPを自動算出する" do
    entry = workout_day.workout_entries.build(exercise: exercise, sets: 4, reps: 10, weight_kg: 0, duration_min: 30, rpe: 5)
    workout_day.save!

    expect(entry.xp).to eq(87)
  end

  it "skip_xp_calculationがtrueなら自動算出せず指定したXPをそのまま保存する(過去データ移行用)" do
    entry = workout_day.workout_entries.build(exercise: exercise, sets: 4, reps: 10, weight_kg: 0, duration_min: 30, rpe: 5)
    entry.xp = 999
    entry.skip_xp_calculation = true
    workout_day.save!

    expect(entry.reload.xp).to eq(999)
  end
end
