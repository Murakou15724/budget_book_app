# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_10_21_000001) do
  create_table "accounts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.integer "kind", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_accounts_on_name", unique: true
  end

  create_table "asset_balances", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "asset_snapshot_id", null: false
    t.bigint "account_id", null: false
    t.integer "balance", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "reconciliation_baseline", default: false, null: false
    t.index ["account_id"], name: "index_asset_balances_on_account_id"
    t.index ["asset_snapshot_id", "account_id"], name: "index_asset_balances_on_snapshot_and_account", unique: true
    t.index ["asset_snapshot_id"], name: "index_asset_balances_on_asset_snapshot_id"
  end

  create_table "asset_snapshots", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "recorded_on", null: false
    t.string "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recorded_on"], name: "index_asset_snapshots_on_recorded_on"
  end

  create_table "badges", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "required_xp", null: false
    t.string "title", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["required_xp"], name: "index_badges_on_required_xp", unique: true
  end

  create_table "categories", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "kind", default: 0, null: false
    t.string "name", null: false
    t.integer "monthly_budget"
    t.string "note"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "name"], name: "index_categories_on_kind_and_name", unique: true
  end

  create_table "category_monthly_budgets", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.integer "year", null: false
    t.integer "month", null: false
    t.integer "budget", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "year", "month"], name: "index_category_monthly_budgets_on_category_year_month", unique: true
    t.index ["category_id"], name: "index_category_monthly_budgets_on_category_id"
  end

  create_table "exercises", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "body_part"
    t.integer "default_sets"
    t.integer "default_reps"
    t.decimal "default_weight_kg", precision: 5, scale: 1
    t.integer "default_duration_min"
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_exercises_on_name", unique: true
  end

  create_table "image_import_drafts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "batch_id", null: false
    t.date "date"
    t.integer "direction"
    t.integer "amount"
    t.string "memo"
    t.bigint "category_id"
    t.bigint "payment_method_id"
    t.bigint "account_id"
    t.integer "credit_card_status", default: 0, null: false
    t.string "suggested_category_name"
    t.string "suggested_payment_method_name"
    t.string "suggested_account_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "credit_card_payment_due_on_override"
    t.bigint "import_entry_id", null: false
    t.string "date_origin", default: "unresolved", null: false
    t.string "transaction_kind", default: "unknown", null: false
    t.json "confirmation_metadata", null: false
    t.json "rule_decision", null: false
    t.bigint "to_account_id"
    t.index ["account_id", "direction", "amount", "date"], name: "index_image_import_drafts_on_import_match"
    t.index ["account_id"], name: "index_image_import_drafts_on_account_id"
    t.index ["batch_id"], name: "index_image_import_drafts_on_batch_id"
    t.index ["category_id"], name: "index_image_import_drafts_on_category_id"
    t.index ["import_entry_id"], name: "index_image_import_drafts_on_import_entry_id", unique: true
    t.index ["payment_method_id"], name: "index_image_import_drafts_on_payment_method_id"
    t.index ["to_account_id"], name: "index_image_import_drafts_on_to_account_id"
  end

  create_table "import_classification_rules", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "import_source_id", null: false
    t.string "channel", limit: 32, null: false
    t.string "merchant_key", null: false
    t.string "direction", limit: 16, null: false
    t.bigint "category_id", null: false
    t.bigint "payment_method_id", null: false
    t.bigint "account_id", null: false
    t.string "credit_card_status", limit: 32, null: false
    t.boolean "enabled", default: false, null: false
    t.integer "priority", default: 100, null: false
    t.integer "version", default: 1, null: false
    t.bigint "confirmation_entry_id"
    t.datetime "confirmed_at", null: false
    t.string "creation_nonce", limit: 36, null: false
    t.string "creation_request_digest", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_import_classification_rules_on_account_id"
    t.index ["category_id"], name: "index_import_classification_rules_on_category_id"
    t.index ["confirmation_entry_id"], name: "index_import_classification_rules_on_confirmation_entry_id"
    t.index ["creation_nonce"], name: "index_import_classification_rules_on_creation_nonce", unique: true
    t.index ["import_source_id", "channel", "enabled"], name: "index_import_rules_on_scope"
    t.index ["import_source_id"], name: "index_import_classification_rules_on_import_source_id"
    t.index ["payment_method_id"], name: "index_import_classification_rules_on_payment_method_id"
  end

  create_table "import_documents", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "import_source_id", null: false
    t.string "channel", null: false
    t.string "content_digest", limit: 64, null: false
    t.string "batch_id", null: false
    t.string "state", null: false
    t.datetime "received_at", null: false
    t.string "mime_type"
    t.bigint "byte_size"
    t.date "manual_date"
    t.date "fallback_date"
    t.string "pipeline_version"
    t.string "error_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_import_documents_on_batch_id"
    t.index ["import_source_id", "channel", "content_digest"], name: "index_import_documents_on_input", unique: true
    t.index ["import_source_id"], name: "index_import_documents_on_import_source_id"
  end

  create_table "import_entries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "import_document_id", null: false
    t.integer "row_number", null: false
    t.bigint "import_identity_id"
    t.bigint "reference_entry_id"
    t.json "payload", null: false
    t.string "payload_digest", limit: 64, null: false
    t.string "classification", null: false
    t.string "state", null: false
    t.string "reason_code"
    t.bigint "target_transaction_id"
    t.json "target_snapshot"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["import_document_id", "row_number"], name: "index_import_entries_on_document_row", unique: true
    t.index ["import_document_id"], name: "index_import_entries_on_import_document_id"
    t.index ["import_identity_id", "payload_digest"], name: "index_import_entries_on_identity_payload"
    t.index ["import_identity_id"], name: "index_import_entries_on_import_identity_id"
    t.index ["reference_entry_id"], name: "index_import_entries_on_reference_entry_id"
    t.index ["target_transaction_id"], name: "index_import_entries_on_target_transaction_id"
  end

  create_table "import_events", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "import_document_id", null: false
    t.bigint "import_entry_id"
    t.string "kind", null: false
    t.string "reason_code"
    t.json "details", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["import_document_id"], name: "index_import_events_on_import_document_id"
    t.index ["import_entry_id"], name: "index_import_events_on_import_entry_id"
  end

  create_table "import_guards", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_import_guards_on_name", unique: true
  end

  create_table "import_identities", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "import_source_id", null: false
    t.text "external_id", null: false
    t.string "external_id_digest", limit: 64, null: false
    t.bigint "bound_entry_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bound_entry_id"], name: "index_import_identities_on_bound_entry_id"
    t.index ["import_source_id", "external_id_digest"], name: "index_import_identities_on_external_key", unique: true
    t.index ["import_source_id"], name: "index_import_identities_on_import_source_id"
  end

  create_table "import_sources", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "service_key", limit: 64, null: false
    t.bigint "account_id"
    t.string "name", null: false
    t.boolean "legacy", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "image_auto_apply_enabled", default: false, null: false
    t.index ["account_id"], name: "index_import_sources_on_account_id"
    t.index ["service_key", "account_id"], name: "index_import_sources_on_service_key_and_account_id", unique: true
  end

  create_table "income_monthly_estimates", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "year", null: false
    t.integer "month", null: false
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["year", "month"], name: "index_income_monthly_estimates_on_year_and_month", unique: true
  end

  create_table "monthly_reviews", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "year", null: false
    t.integer "month", null: false
    t.integer "satisfaction"
    t.text "regret_note"
    t.text "good_spending_note"
    t.text "next_month_cut_note"
    t.text "comment"
    t.text "next_action"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["year", "month"], name: "index_monthly_reviews_on_year_and_month", unique: true
  end

  create_table "payment_methods", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "note"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "import_kind", default: "unknown", null: false
    t.index ["name"], name: "index_payment_methods_on_name", unique: true
  end

  create_table "quick_entry_templates", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.integer "direction", default: 1, null: false
    t.bigint "category_id"
    t.bigint "payment_method_id", null: false
    t.bigint "account_id", null: false
    t.integer "credit_card_status", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "to_account_id"
    t.index ["account_id"], name: "index_quick_entry_templates_on_account_id"
    t.index ["category_id"], name: "index_quick_entry_templates_on_category_id"
    t.index ["name"], name: "index_quick_entry_templates_on_name", unique: true
    t.index ["payment_method_id"], name: "index_quick_entry_templates_on_payment_method_id"
    t.index ["to_account_id"], name: "index_quick_entry_templates_on_to_account_id"
  end

  create_table "settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "target_year"
    t.integer "total_savings_goal"
    t.integer "monthly_savings_goal"
    t.integer "level_unit_amount", default: 10000, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "image_import_requires_approval", default: true, null: false
    t.integer "credit_card_closing_day", default: 31, null: false
    t.integer "credit_card_payment_day", default: 26, null: false
    t.bigint "credit_card_payment_account_id"
    t.integer "monthly_income_estimate"
    t.index ["credit_card_payment_account_id"], name: "index_settings_on_credit_card_payment_account_id"
  end

  create_table "transactions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "date", null: false
    t.integer "entry_type", default: 0, null: false
    t.integer "direction", null: false
    t.bigint "category_id"
    t.integer "amount", null: false
    t.bigint "payment_method_id", null: false
    t.bigint "account_id", null: false
    t.text "memo"
    t.integer "satisfaction"
    t.boolean "regret", default: false, null: false
    t.integer "credit_card_status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "credit_card_payment_due_on_override"
    t.bigint "to_account_id"
    t.date "credit_card_paid_on"
    t.index ["account_id", "direction", "amount", "date"], name: "index_transactions_on_import_match"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["credit_card_paid_on"], name: "index_transactions_on_credit_card_paid_on"
    t.index ["date"], name: "index_transactions_on_date"
    t.index ["direction", "entry_type"], name: "index_transactions_on_direction_and_entry_type"
    t.index ["payment_method_id"], name: "index_transactions_on_payment_method_id"
    t.index ["to_account_id"], name: "index_transactions_on_to_account_id"
  end

  create_table "weekly_reviews", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "week_start_date", null: false
    t.text "win_pattern"
    t.text "next_week_adjustment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["week_start_date"], name: "index_weekly_reviews_on_week_start_date", unique: true
  end

  create_table "workout_days", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "date", null: false
    t.integer "status", default: 0, null: false
    t.string "mood"
    t.text "memo"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_workout_days_on_date", unique: true
  end

  create_table "workout_entries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "workout_day_id", null: false
    t.bigint "exercise_id", null: false
    t.integer "sets"
    t.integer "reps"
    t.decimal "weight_kg", precision: 5, scale: 1
    t.integer "duration_min"
    t.integer "rpe"
    t.integer "xp", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exercise_id"], name: "index_workout_entries_on_exercise_id"
    t.index ["workout_day_id"], name: "index_workout_entries_on_workout_day_id"
  end

  create_table "workout_settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "start_date", null: false
    t.integer "weekly_goal_count", default: 5, null: false
    t.integer "weekly_goal_xp", default: 300, null: false
    t.string "current_goal_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "asset_balances", "accounts"
  add_foreign_key "asset_balances", "asset_snapshots"
  add_foreign_key "category_monthly_budgets", "categories"
  add_foreign_key "image_import_drafts", "accounts"
  add_foreign_key "image_import_drafts", "accounts", column: "to_account_id"
  add_foreign_key "image_import_drafts", "categories"
  add_foreign_key "image_import_drafts", "import_entries"
  add_foreign_key "image_import_drafts", "payment_methods"
  add_foreign_key "import_classification_rules", "accounts"
  add_foreign_key "import_classification_rules", "categories"
  add_foreign_key "import_classification_rules", "import_entries", column: "confirmation_entry_id"
  add_foreign_key "import_classification_rules", "import_sources"
  add_foreign_key "import_classification_rules", "payment_methods"
  add_foreign_key "import_documents", "import_sources"
  add_foreign_key "import_entries", "import_documents"
  add_foreign_key "import_entries", "import_entries", column: "reference_entry_id"
  add_foreign_key "import_entries", "import_identities"
  add_foreign_key "import_events", "import_documents"
  add_foreign_key "import_events", "import_entries"
  add_foreign_key "import_identities", "import_entries", column: "bound_entry_id"
  add_foreign_key "import_identities", "import_sources"
  add_foreign_key "import_sources", "accounts"
  add_foreign_key "quick_entry_templates", "accounts"
  add_foreign_key "quick_entry_templates", "accounts", column: "to_account_id"
  add_foreign_key "quick_entry_templates", "categories"
  add_foreign_key "quick_entry_templates", "payment_methods"
  add_foreign_key "settings", "accounts", column: "credit_card_payment_account_id"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "accounts", column: "to_account_id"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "payment_methods"
  add_foreign_key "workout_entries", "exercises"
  add_foreign_key "workout_entries", "workout_days"
end
