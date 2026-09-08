class CreateWorkoutSettings < ActiveRecord::Migration[7.1]
  def change
    # Settingと同様、常に1行のみ使うシングルトンテーブル。
    create_table :workout_settings do |t|
      t.date :start_date, null: false
      t.integer :weekly_goal_count, null: false, default: 5
      t.integer :weekly_goal_xp, null: false, default: 300
      t.string :current_goal_text

      t.timestamps
    end
  end
end
