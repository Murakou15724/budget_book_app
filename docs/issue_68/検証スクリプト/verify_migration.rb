require "json"
require "securerandom"
require_relative "/home/murakamiko/projects/budget_book_app/config/environment"
raise "dedicated database required" unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == "budget_book_app_test_68"
connection = ActiveRecord::Base.connection
config = ActiveRecord::Base.connection_db_config.configuration_hash
expected_port = connection.adapter_name == "Mysql2" ? 13368 : 15368
raise "dedicated localhost required" unless config[:host] == "127.0.0.1" && config[:port].to_i == expected_port
root = "/home/murakamiko/projects/budget_book_app"
baseline = "/tmp/budget-book-68-validation/baseline/db/schema.rb"
current = File.join(root, "db/schema.rb")
adapter = connection.adapter_name
record = ->(table) { Class.new(ActiveRecord::Base) { self.table_name = table } }

# このスクリプトは利用者が専用使い捨てDBへ手動実行する。
connection.disable_referential_integrity do
  connection.drop_table(:import_classification_rules, if_exists: true)
  load baseline
end
now = Time.current
account = record.call("accounts").create!(name: "移行元", kind: 0)
category = record.call("categories").create!(name: "移行分類", kind: 0)
payment = record.call("payment_methods").create!(name: "移行支払")
source = record.call("import_sources").create!(name: "移行取込元", service_key: "migration", account_id: account.id)
document = record.call("import_documents").create!(import_source_id: source.id, channel: "image", content_digest: "a" * 64,
  batch_id: "migration", state: "extracted", received_at: now, manual_date: "2026-09-05", fallback_date: "2026-09-01")
entry = record.call("import_entries").create!(import_document_id: document.id, row_number: 1, payload: { "date" => "old-raw", "amount" => "001000" },
  payload_digest: "b" * 64, classification: "new", state: "pending", target_snapshot: { "memo" => "old snapshot" })
draft = record.call("image_import_drafts").create!(import_entry_id: entry.id, batch_id: "migration", date: "2026-09-02", direction: 1,
  amount: 1000, category_id: category.id, payment_method_id: payment.id, account_id: account.id, memo: "既存候補")
transaction = record.call("transactions").create!(date: "2026-09-02", entry_type: 0, direction: 1, amount: 1000,
  category_id: category.id, payment_method_id: payment.id, account_id: account.id, memo: "既存実績")
before = [document, entry, draft, transaction].to_h { |model| [model.class.table_name, model.reload.attributes] }
load File.join(root, "db/migrate/20261021000001_add_import_classification.rb")
interrupted = AddImportClassification.new
interrupted.define_singleton_method(:add_column) do |table, column, *args, **options|
  raise "injected DDL interruption" if table == :image_import_drafts && column == :rule_decision
  super(table, column, *args, **options)
end
begin
  interrupted.migrate(:up)
  raise "injection did not occur"
rescue RuntimeError => error
  raise unless error.message == "injected DDL interruption"
end
AddImportClassification.new.migrate(:up)
AddImportClassification.new.migrate(:up)
connection.schema_cache.clear!
before.each do |table, values|
  after = record.call(table).find(values["id"]).attributes.slice(*values.keys)
  raise "existing #{table} changed" unless after == values
end
upgraded = record.call("image_import_drafts").find(draft.id)
raise "legacy defaults" unless upgraded.date_origin == "unresolved" && upgraded.transaction_kind == "unknown" &&
  upgraded.confirmation_metadata == {} && upgraded.rule_decision == {}
column = connection.columns(:image_import_drafts).find { |item| item.name == "direction" }
raise "direction constraints" unless column.null && column.default.nil?
raise "source permission" unless record.call("import_sources").find(source.id).image_auto_apply_enabled == false
raise "payment default" unless record.call("payment_methods").find(payment.id).import_kind == "unknown"
raise "initial rules" unless record.call("import_classification_rules").count == 0
raise "draft FK" unless connection.foreign_key_exists?(:image_import_drafts, column: :to_account_id)
%i[import_source_id category_id payment_method_id account_id confirmation_entry_id].each do |column|
  raise "rule FK #{column}" unless connection.foreign_key_exists?(:import_classification_rules, column: column)
end
begin
  AddImportClassification.new.down
  raise "down unexpectedly succeeded"
rescue ActiveRecord::IrreversibleMigration
end
%w[image_import_drafts import_events import_entries import_identities import_documents transactions import_sources categories payment_methods accounts settings import_guards].each do |table|
  record.call(table).delete_all
end
migration_log = "/tmp/budget-book-68-validation/#{adapter.downcase}-migration-final.log"
migration_tests = system("bundle", "exec", "rspec", "--format", "progress", out: migration_log, err: [:child, :out])
connection.disable_referential_integrity { load current }
schema_log = "/tmp/budget-book-68-validation/#{adapter.downcase}-schema-final.log"
schema_tests = system("bundle", "exec", "rspec", "--format", "progress", out: schema_log, err: [:child, :out])
File.write("/tmp/budget-book-68-validation/migration-#{adapter.downcase}.json", JSON.pretty_generate({
  adapter: adapter, preserved_tables: before.keys, interrupted_ddl_resume: true, repeat_up: true,
  legacy_defaults: true, direction_nullable_without_default: true, foreign_keys: 6, irreversible_down: true,
  final_schema_load: true, migration_tests_success: migration_tests, schema_tests_success: schema_tests }) + "\n")
puts "Migration preservation / interrupted resume / schema reload: PASS (#{adapter})"
puts "RSpec migration: #{migration_tests ? 'PASS' : 'FAIL'}; schema: #{schema_tests ? 'PASS' : 'FAIL'}"
exit(migration_tests && schema_tests ? 0 : 1)
