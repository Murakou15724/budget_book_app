class CreateSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :settings do |t|
      t.integer :target_year
      t.integer :total_savings_goal
      t.integer :monthly_savings_goal
      t.integer :level_unit_amount, null: false, default: 10000

      t.timestamps
    end
  end
end
