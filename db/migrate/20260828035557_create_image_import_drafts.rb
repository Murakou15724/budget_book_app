class CreateImageImportDrafts < ActiveRecord::Migration[7.1]
  def change
    create_table :image_import_drafts do |t|
      t.string :batch_id, null: false
      t.date :date
      t.integer :direction, null: false, default: 1
      t.integer :amount
      t.string :memo
      t.references :category, foreign_key: true
      t.references :payment_method, foreign_key: true
      t.references :account, foreign_key: true
      t.integer :credit_card_status, null: false, default: 0
      t.string :suggested_category_name
      t.string :suggested_payment_method_name
      t.string :suggested_account_name

      t.timestamps
    end
    add_index :image_import_drafts, :batch_id
  end
end
