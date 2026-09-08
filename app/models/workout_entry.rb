class WorkoutEntry < ApplicationRecord
  belongs_to :workout_day
  belongs_to :exercise

  validates :sets, :reps, :duration_min, :rpe, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :weight_kg, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # 過去データのインポート時は、Excel側の計算済みXPをそのまま保存したいので
  # (計算式の見直しで過去実績の数値が変動するのを防ぐため)、
  # このフラグを立てるとXPの自動算出をスキップする。
  attr_accessor :skip_xp_calculation

  before_save :assign_xp, unless: :skip_xp_calculation

  # Excelの数式 =ROUND(セット*回数*MAX(重量,1)/20 + 時間*2 + RPE*5) を踏襲。
  def self.calculate_xp(sets:, reps:, weight_kg:, duration_min:, rpe:)
    volume = (sets.to_i * reps.to_i * [weight_kg.to_f, 1].max) / 20.0
    (volume + duration_min.to_i * 2 + rpe.to_i * 5).round
  end

  private

  def assign_xp
    self.xp = self.class.calculate_xp(sets: sets, reps: reps, weight_kg: weight_kg, duration_min: duration_min, rpe: rpe)
  end
end
