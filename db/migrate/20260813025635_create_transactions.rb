class CreateTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :transactions do |t|
      t.date :date, null: false
      t.integer :entry_type, null: false, default: 0
      t.integer :direction, null: false
      t.references :category, null: false, foreign_key: true
      t.integer :amount, null: false
      t.references :payment_method, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.text :memo
      t.integer :satisfaction
      t.boolean :regret, null: false, default: false
      t.integer :credit_card_status, null: false, default: 0

      t.timestamps
    end
    add_index :transactions, :date
    add_index :transactions, [:direction, :entry_type]
  end
end
