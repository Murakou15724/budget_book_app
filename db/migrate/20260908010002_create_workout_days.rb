class CreateWorkoutDays < ActiveRecord::Migration[7.1]
  def change
    # Excelのように366日分を事前に用意せず、実際に記録がある日のみ行を作る。
    # 行が存在しない日は「未記録」を意味し、連続日数の算出上は休みと同じ扱いにする。
    create_table :workout_days do |t|
      t.date :date, null: false
      t.integer :status, null: false, default: 0
      t.string :mood
      t.text :memo

      t.timestamps
    end
    add_index :workout_days, :date, unique: true
  end
end
