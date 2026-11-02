require "json"
require_relative "../../../config/environment"

connection = ActiveRecord::Base.connection
config = ActiveRecord::Base.connection_db_config.configuration_hash
adapter = { "Mysql2" => "mysql2", "PostgreSQL" => "postgresql" }.fetch(connection.adapter_name)
port = adapter == "mysql2" ? 13369 : 15369
raise "dedicated test database required" unless Rails.env.test? && config[:database] == "budget_book_app_test_69" &&
  config[:host] == "127.0.0.1" && config[:port].to_i == port

root = Rails.root.to_s
output = "/tmp/budget-book-69-validation"
baseline = File.join(output, "baseline-schema.rb")
current = File.join(root, "db/schema.rb")
record = ->(table) { Class.new(ActiveRecord::Base) { self.table_name = table } }
connection.disable_referential_integrity do
  if connection.foreign_key_exists?(:import_classification_rules, :import_payment_routes)
    connection.remove_foreign_key(:import_classification_rules, :import_payment_routes)
  end
  connection.drop_table(:import_payment_routes, if_exists: true)
  load baseline
end
account = record.call("accounts").create!(name: "架空既存口座", kind: 0)
category = record.call("categories").create!(name: "架空既存費目", kind: 1)
payment = record.call("payment_methods").create!(name: "架空既存支払", import_kind: "bank")
source = record.call("import_sources").create!(name: "架空既存元", service_key: "existing", account_id: account.id, image_auto_apply_enabled: true)
document = record.call("import_documents").create!(import_source_id: source.id, channel: "image", content_digest: "a" * 64,
  batch_id: "migration-69", state: "extracted", received_at: Time.current)
identity = record.call("import_identities").create!(import_source_id: source.id, external_id: "000-Aa", external_id_digest: "c" * 64)
entry = record.call("import_entries").create!(import_document_id: document.id, import_identity_id: identity.id, row_number: 1,
  payload: { "amount" => "001", "merchant" => "架空既存" }, payload_digest: "b" * 64, classification: "new", state: "held")
draft = record.call("image_import_drafts").create!(import_entry_id: entry.id, batch_id: "migration-69", amount: 1,
  confirmation_metadata: { "version" => 1 }, rule_decision: {})
transaction = record.call("transactions").create!(date: "2026-10-01", direction: 1, amount: 1,
  category_id: category.id, payment_method_id: payment.id, account_id: account.id, memo: "架空既存実績")
rule = record.call("import_classification_rules").create!(import_source_id: source.id, channel: "image", merchant_key: "架空既存",
  direction: "expense", category_id: category.id, payment_method_id: payment.id, account_id: account.id,
  credit_card_status: "not_applicable", creation_nonce: "migration-69", creation_request_digest: "d" * 64, confirmed_at: Time.current)
before = [account, category, payment, source, document, identity, entry, draft, transaction, rule].map { |item| [item.class.table_name, item.id, item.attributes] }
load File.join(root, "db/migrate/20261030090000_add_paypay_csv_import.rb")
interrupted = AddPaypayCsvImport.new
interrupted.define_singleton_method(:add_foreign_key) do |table, other, **options|
  raise "injected DDL interruption" if table == :import_classification_rules && other == :import_payment_routes
  super(table, other, **options)
end
begin
  interrupted.migrate(:up)
  raise "interruption did not occur"
rescue RuntimeError => error
  raise unless error.message == "injected DDL interruption"
end
AddPaypayCsvImport.new.migrate(:up)
AddPaypayCsvImport.new.migrate(:up)
connection.schema_cache.clear!
before.each do |table, id, values|
  raise "existing data changed: #{table}" unless record.call(table).find(id).attributes.slice(*values.keys) == values
end
raise "CSV permission default" unless record.call("import_sources").find(source.id).csv_auto_apply_enabled == false
raise "initial routes" unless record.call("import_payment_routes").count.zero?
raise "image rule route" unless record.call("import_classification_rules").find(rule.id).import_payment_route_id.nil?
%i[import_source_id account_id payment_method_id].each do |column|
  raise "missing route FK" unless connection.foreign_key_exists?(:import_payment_routes, column: column)
end
raise "missing rule FK" unless connection.foreign_key_exists?(:import_classification_rules, :import_payment_routes)
raise "missing unique index" unless connection.index_exists?(:import_payment_routes, [:import_source_id, :source_method_digest], unique: true)
column = connection.columns(:import_identities).find { |item| item.name == "external_id" }
raise "external ID constraints" if column.null || (adapter == "mysql2" && column.sql_type != "mediumtext")
begin
  AddPaypayCsvImport.new.down
  raise "down succeeded unexpectedly"
rescue ActiveRecord::IrreversibleMigration
end
connection.disable_referential_integrity do
  connection.tables.each do |table|
    next if %w[schema_migrations ar_internal_metadata].include?(table)
    record.call(table).delete_all
  end
end
connection.schema_cache.clear!
migration_log = File.join(output, "#{adapter}-migration-final.log")
migration_success = system("bundle", "exec", "rspec", "--format", "progress", out: migration_log, err: [:child, :out])
connection.disable_referential_integrity { load current }
connection.schema_cache.clear!
raise "schema defaults" unless record.call("import_payment_routes").count.zero?
schema_log = File.join(output, "#{adapter}-schema-final.log")
schema_success = system("bundle", "exec", "rspec", "--format", "progress", out: schema_log, err: [:child, :out])
result = { adapter: adapter, database: config[:database], port: port, preserved_tables: before.map(&:first),
  interrupted_ddl_resume: true, repeat_up: true, foreign_keys: 4, unique_index: true,
  csv_permission_default_false: true, routes_initially_empty: true, external_id_type: column.sql_type,
  irreversible_down: true, migration_tests_success: migration_success, schema_tests_success: schema_success }
File.write(File.join(output, "migration-#{adapter}.json"), JSON.pretty_generate(result) + "\n")
puts "#{adapter}: migration #{migration_success ? 'PASS' : 'FAIL'}, schema #{schema_success ? 'PASS' : 'FAIL'}"
exit(migration_success && schema_success ? 0 : 1)
