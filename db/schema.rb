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

ActiveRecord::Schema[7.1].define(version: 2026_09_02_073040) do
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

  create_table "image_import_drafts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "batch_id", null: false
    t.date "date"
    t.integer "direction", default: 1, null: false
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
    t.index ["account_id"], name: "index_image_import_drafts_on_account_id"
    t.index ["batch_id"], name: "index_image_import_drafts_on_batch_id"
    t.index ["category_id"], name: "index_image_import_drafts_on_category_id"
    t.index ["payment_method_id"], name: "index_image_import_drafts_on_payment_method_id"
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
    t.index ["name"], name: "index_payment_methods_on_name", unique: true
  end

  create_table "quick_entry_templates", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.integer "direction", default: 1, null: false
    t.bigint "category_id", null: false
    t.bigint "payment_method_id", null: false
    t.bigint "account_id", null: false
    t.integer "credit_card_status", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_quick_entry_templates_on_account_id"
    t.index ["category_id"], name: "index_quick_entry_templates_on_category_id"
    t.index ["name"], name: "index_quick_entry_templates_on_name", unique: true
    t.index ["payment_method_id"], name: "index_quick_entry_templates_on_payment_method_id"
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
  end

  create_table "transactions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.date "date", null: false
    t.integer "entry_type", default: 0, null: false
    t.integer "direction", null: false
    t.bigint "category_id", null: false
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
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["date"], name: "index_transactions_on_date"
    t.index ["direction", "entry_type"], name: "index_transactions_on_direction_and_entry_type"
    t.index ["payment_method_id"], name: "index_transactions_on_payment_method_id"
  end

  add_foreign_key "asset_balances", "accounts"
  add_foreign_key "asset_balances", "asset_snapshots"
  add_foreign_key "category_monthly_budgets", "categories"
  add_foreign_key "image_import_drafts", "accounts"
  add_foreign_key "image_import_drafts", "categories"
  add_foreign_key "image_import_drafts", "payment_methods"
  add_foreign_key "quick_entry_templates", "accounts"
  add_foreign_key "quick_entry_templates", "categories"
  add_foreign_key "quick_entry_templates", "payment_methods"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "payment_methods"
end
