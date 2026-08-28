class CreateQuickEntryTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :quick_entry_templates do |t|
      t.string :name, null: false
      t.integer :direction, null: false, default: 1
      t.references :category, null: false, foreign_key: true
      t.references :payment_method, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.integer :credit_card_status, null: false, default: 0
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :quick_entry_templates, :name, unique: true
  end
end
