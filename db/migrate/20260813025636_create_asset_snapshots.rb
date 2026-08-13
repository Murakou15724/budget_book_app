class CreateAssetSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :asset_snapshots do |t|
      t.date :recorded_on, null: false
      t.string :memo

      t.timestamps
    end
    add_index :asset_snapshots, :recorded_on
  end
end
