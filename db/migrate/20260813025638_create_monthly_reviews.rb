class CreateMonthlyReviews < ActiveRecord::Migration[7.1]
  def change
    create_table :monthly_reviews do |t|
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :satisfaction
      t.text :regret_note
      t.text :good_spending_note
      t.text :next_month_cut_note
      t.text :comment
      t.text :next_action

      t.timestamps
    end
    add_index :monthly_reviews, [:year, :month], unique: true
  end
end
