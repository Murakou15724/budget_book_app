require "digest"

class CreateImportTracking < ActiveRecord::Migration[7.1]
  def up
    create_table :import_sources, if_not_exists: true do |t|
      t.string :service_key, limit: 64, null: false
      t.references :account, foreign_key: true
      t.string :name, null: false
      t.boolean :legacy, default: false, null: false
      t.timestamps
      t.index [:service_key, :account_id], unique: true
    end
    create_table :import_documents, if_not_exists: true do |t|
      t.references :import_source, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :content_digest, limit: 64, null: false
      t.string :batch_id, null: false, index: true
      t.string :state, null: false
      t.datetime :received_at, null: false
      t.string :mime_type
      t.bigint :byte_size
      t.date :manual_date
      t.date :fallback_date
      t.string :pipeline_version
      t.string :error_code
      t.timestamps
      t.index [:import_source_id, :channel, :content_digest], unique: true, name: "index_import_documents_on_input"
    end
    create_table :import_identities, if_not_exists: true do |t|
      t.references :import_source, null: false, foreign_key: true
      t.text :external_id, null: false
      t.string :external_id_digest, limit: 64, null: false
      t.bigint :bound_entry_id, index: true
      t.timestamps
      t.index [:import_source_id, :external_id_digest], unique: true, name: "index_import_identities_on_external_key"
    end
    create_table :import_entries, if_not_exists: true do |t|
      t.references :import_document, null: false, foreign_key: true
      t.integer :row_number, null: false
      t.references :import_identity, foreign_key: true
      t.bigint :reference_entry_id, index: true
      t.json :payload, null: false
      t.string :payload_digest, limit: 64, null: false
      t.string :classification, null: false
      t.string :state, null: false
      t.string :reason_code
      t.bigint :target_transaction_id, index: true
      t.json :target_snapshot
      t.integer :lock_version, default: 0, null: false
      t.timestamps
      t.index [:import_document_id, :row_number], unique: true, name: "index_import_entries_on_document_row"
      t.index [:import_identity_id, :payload_digest], name: "index_import_entries_on_identity_payload"
    end
    add_foreign_key :import_entries, :import_entries, column: :reference_entry_id unless foreign_key_exists?(:import_entries, column: :reference_entry_id)
    add_foreign_key :import_identities, :import_entries, column: :bound_entry_id unless foreign_key_exists?(:import_identities, column: :bound_entry_id)
    create_table :import_events, if_not_exists: true do |t|
      t.references :import_document, null: false, foreign_key: true
      t.references :import_entry, foreign_key: true
      t.string :kind, null: false
      t.string :reason_code
      t.json :details, null: false
      t.timestamps
    end
    create_table :import_guards, if_not_exists: true do |t|
      t.string :name, null: false, index: { unique: true }
      t.timestamps
    end
    add_column :image_import_drafts, :import_entry_id, :bigint unless column_exists?(:image_import_drafts, :import_entry_id)
    add_index :image_import_drafts, :import_entry_id, unique: true, if_not_exists: true
    add_foreign_key :image_import_drafts, :import_entries unless foreign_key_exists?(:image_import_drafts, :import_entries)
    [:transactions, :image_import_drafts].each do |table|
      add_index table, [:account_id, :direction, :amount, :date], name: "index_#{table}_on_import_match", if_not_exists: true
    end
    backfill
    change_column_null :image_import_drafts, :import_entry_id, false
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "取込履歴を保持するため自動的には戻せません"
  end

  private

  def record_class(table)
    Class.new(ActiveRecord::Base) { self.table_name = table }
  end

  def backfill
    source = record_class("import_sources").find_or_create_by!(service_key: "legacy_image", account_id: nil) do |s|
      s.name = "移行前の画像候補（元口座不明）"
      s.legacy = true
    end
    record_class("import_guards").find_or_create_by!(name: "ledger")
    documents = record_class("import_documents")
    entries = record_class("import_entries")
    events = record_class("import_events")
    drafts = record_class("image_import_drafts")
    drafts.reset_column_information
    drafts.where(import_entry_id: nil).find_each do |draft|
      # 各行の紐付けまで一括commit。MySQLのDDL途中失敗後も再実行可能。
      drafts.transaction do
        document = documents.find_or_create_by!(import_source_id: source.id, channel: "legacy",
          content_digest: Digest::SHA256.hexdigest("legacy_batch:#{draft.batch_id}")) do |d|
          d.assign_attributes(batch_id: draft.batch_id, state: "extracted", received_at: draft.created_at,
            fallback_date: draft.created_at.to_date, pipeline_version: "legacy")
        end
        payload = draft.attributes.slice("date", "direction", "amount", "memo").merge("origin" => "legacy_current_values")
        entry = entries.find_or_create_by!(import_document_id: document.id, row_number: draft.id) do |e|
          e.assign_attributes(payload: payload, payload_digest: Digest::SHA256.hexdigest(payload.to_json),
            classification: "hold", state: "held", reason_code: "legacy_origin_unknown")
        end
        draft.update!(import_entry_id: entry.id)
        events.create!(import_document_id: document.id, import_entry_id: entry.id,
          kind: "migrated", reason_code: "legacy_origin_unknown", details: { "input_kind" => "legacy" })
      end
    end
  end
end
