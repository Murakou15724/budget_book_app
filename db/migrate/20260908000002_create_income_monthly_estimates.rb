class CreateIncomeMonthlyEstimates < ActiveRecord::Migration[7.1]
  def change
    # 「収入見込み」(settings.monthly_income_estimate)の月別上書き。
    # category_monthly_budgetsと同じ構造だが、単一のプランなのでcategory_idは持たない。
    create_table :income_monthly_estimates do |t|
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :amount, null: false

      t.timestamps
    end
    add_index :income_monthly_estimates, [:year, :month], unique: true
  end
end
