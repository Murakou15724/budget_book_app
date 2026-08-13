class CreateAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.integer :kind, null: false, default: 0
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :accounts, :name, unique: true
  end
end
