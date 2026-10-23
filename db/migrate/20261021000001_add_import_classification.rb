class AddImportClassification < ActiveRecord::Migration[7.1]
  def up
    add_column :import_sources, :image_auto_apply_enabled, :boolean, null: false, default: false unless column_exists?(:import_sources, :image_auto_apply_enabled)
    add_column :payment_methods, :import_kind, :string, null: false, default: "unknown" unless column_exists?(:payment_methods, :import_kind)
    change_column_null :image_import_drafts, :direction, true
    change_column_default :image_import_drafts, :direction, nil
    { date_origin: "unresolved", transaction_kind: "unknown" }.each do |column, default|
      add_column :image_import_drafts, column, :string, null: false, default: default unless column_exists?(:image_import_drafts, column)
    end
    %i[confirmation_metadata rule_decision].each do |column|
      add_column :image_import_drafts, column, :json unless column_exists?(:image_import_drafts, column)
      model = Class.new(ActiveRecord::Base) { self.table_name = "image_import_drafts" }
      model.reset_column_information
      model.where(column => nil).update_all(column => {})
      change_column_null :image_import_drafts, column, false
    end
    add_column :image_import_drafts, :to_account_id, :bigint unless column_exists?(:image_import_drafts, :to_account_id)
    add_index :image_import_drafts, :to_account_id, if_not_exists: true
    add_foreign_key :image_import_drafts, :accounts, column: :to_account_id unless foreign_key_exists?(:image_import_drafts, column: :to_account_id)
    create_table :import_classification_rules, if_not_exists: true do |t|
      t.bigint :import_source_id, null: false
      t.string :channel, limit: 32, null: false
      t.string :merchant_key, limit: 255, null: false
      t.string :direction, limit: 16, null: false
      t.bigint :category_id, null: false
      t.bigint :payment_method_id, null: false
      t.bigint :account_id, null: false
      t.string :credit_card_status, limit: 32, null: false
      t.boolean :enabled, null: false, default: false
      t.integer :priority, null: false, default: 100
      t.integer :version, null: false, default: 1
      t.bigint :confirmation_entry_id
      t.datetime :confirmed_at, null: false
      t.string :creation_nonce, limit: 36, null: false
      t.string :creation_request_digest, limit: 64, null: false
      t.timestamps
    end
    add_index :import_classification_rules, [:import_source_id, :channel, :enabled], name: "index_import_rules_on_scope", if_not_exists: true
    add_index :import_classification_rules, :creation_nonce, unique: true, if_not_exists: true
    { import_source_id: :import_sources, category_id: :categories, payment_method_id: :payment_methods,
      account_id: :accounts, confirmation_entry_id: :import_entries }.each do |column, table|
      add_index :import_classification_rules, column, if_not_exists: true
      add_foreign_key :import_classification_rules, table, column: column unless foreign_key_exists?(:import_classification_rules, column: column)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "確認済みルール・取込の判断履歴を保持します"
  end
end
