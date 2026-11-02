class AddPaypayCsvImport < ActiveRecord::Migration[7.1]
  def up
    create_table :import_payment_routes, if_not_exists: true do |t|
      t.bigint :import_source_id, null: false
      t.bigint :account_id, null: false
      t.bigint :payment_method_id, null: false
      t.string :source_method, null: false
      t.string :source_method_digest, limit: 64, null: false
      t.string :credit_card_status, limit: 32, null: false
      t.boolean :enabled, null: false, default: false
      t.integer :version, null: false, default: 1
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :import_payment_routes, [:import_source_id, :source_method_digest], unique: true,
      name: "index_import_routes_on_source_method", if_not_exists: true
    { import_source_id: :import_sources, account_id: :accounts, payment_method_id: :payment_methods }.each do |column, table|
      add_index :import_payment_routes, column, if_not_exists: true unless column == :import_source_id
      add_foreign_key :import_payment_routes, table, column: column unless foreign_key_exists?(:import_payment_routes, column: column)
    end
    add_column :import_sources, :csv_auto_apply_enabled, :boolean, null: false, default: false unless column_exists?(:import_sources, :csv_auto_apply_enabled)
    add_column :import_classification_rules, :import_payment_route_id, :bigint unless column_exists?(:import_classification_rules, :import_payment_route_id)
    add_index :import_classification_rules, :import_payment_route_id, if_not_exists: true
    unless foreign_key_exists?(:import_classification_rules, :import_payment_routes)
      add_foreign_key :import_classification_rules, :import_payment_routes
    end
    column = connection.columns(:import_identities).find { |item| item.name == "external_id" }
    unless connection.adapter_name == "Mysql2" && %w[mediumtext longtext].include?(column.sql_type.downcase)
      change_column :import_identities, :external_id, :text, limit: 16_777_215, null: false
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "取込履歴と設定を保持するため自動的には戻せません"
  end
end
