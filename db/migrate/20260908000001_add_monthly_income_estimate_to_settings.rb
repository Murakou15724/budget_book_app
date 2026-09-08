class AddMonthlyIncomeEstimateToSettings < ActiveRecord::Migration[7.1]
  def change
    # budget_plan画面で設定する「収入見込み(基本手取り月収)」の基本値。
    add_column :settings, :monthly_income_estimate, :integer
  end
end
