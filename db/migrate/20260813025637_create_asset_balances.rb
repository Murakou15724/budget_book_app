class CreateAssetBalances < ActiveRecord::Migration[7.1]
  def change
    create_table :asset_balances do |t|
      t.references :asset_snapshot, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.integer :balance, null: false

      t.timestamps
    end
    add_index :asset_balances, [:asset_snapshot_id, :account_id], unique: true, name: "index_asset_balances_on_snapshot_and_account"
  end
end
