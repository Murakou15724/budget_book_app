class AddReconciliationBaselineToAssetBalances < ActiveRecord::Migration[7.1]
  def change
    # 残高整合性チェックで、前回スナップショットとの比較をせず、この残高を集計の起点とする口座残高。
    add_column :asset_balances, :reconciliation_baseline, :boolean, default: false, null: false
  end
end
