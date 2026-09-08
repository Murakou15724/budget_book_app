class CreateWorkoutEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :workout_entries do |t|
      t.references :workout_day, null: false, foreign_key: true
      t.references :exercise, null: false, foreign_key: true
      t.integer :sets
      t.integer :reps
      t.decimal :weight_kg, precision: 5, scale: 1
      t.integer :duration_min
      t.integer :rpe
      t.integer :xp, null: false, default: 0

      t.timestamps
    end
  end
end
