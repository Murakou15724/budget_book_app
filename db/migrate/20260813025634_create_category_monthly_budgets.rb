class CreateCategoryMonthlyBudgets < ActiveRecord::Migration[7.1]
  def change
    create_table :category_monthly_budgets do |t|
      t.references :category, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :budget, null: false

      t.timestamps
    end
    add_index :category_monthly_budgets, [:category_id, :year, :month], unique: true, name: "index_category_monthly_budgets_on_category_year_month"
  end
end
