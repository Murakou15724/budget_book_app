class CreateWeeklyReviews < ActiveRecord::Migration[7.1]
  def change
    # 実施回数・合計XP・平均RPEなどの集計値はworkout_daysから都度算出するため保持しない。
    create_table :weekly_reviews do |t|
      t.date :week_start_date, null: false
      t.text :win_pattern
      t.text :next_week_adjustment

      t.timestamps
    end
    add_index :weekly_reviews, :week_start_date, unique: true
  end
end
