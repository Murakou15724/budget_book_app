require "json"
require "stringio"
require "securerandom"
root, mode, output = ARGV
require File.join(root, "config/environment")
require "rack/test"
require "nokogiri"
raise "dedicated database required" unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == "budget_book_app_test_68"
config = ActiveRecord::Base.connection_db_config.configuration_hash
raise "dedicated localhost required" unless config[:host] == "127.0.0.1" && [13368, 15368].include?(config[:port].to_i)
if mode == "before" && ImageImportDraft.column_names.include?("confirmation_metadata")
  # 旧アプリを追加列のある検証DBで動かすため、未使用の管理JSON列だけ初期化する。
  ImageImportDraft.after_initialize do
    self.confirmation_metadata ||= {}
    self.rule_decision ||= {}
  end
end

ActiveRecord::Base.transaction do
  tag = "comparison68"
  account = Account.create!(name: "比較元-#{tag}", kind: :bank)
  category = Category.create!(name: "比較分類-#{tag}", kind: :expense)
  payment = PaymentMethod.create!(name: "比較銀行-#{tag}")
  source = ImportSource.create!(name: "比較サービス-#{tag}", service_key: "measure-#{tag}", account: account)
  items = 10.times.map do |index|
    { "date" => "2026-10-01", "raw_date" => "2026-10-01", "date_year_explicit" => true,
      "direction" => "expense", "amount" => 1000 + index, "memo" => "比較店", "merchant" => "比較店",
      "transaction_kind" => "normal", "uncertain_fields" => [], "evidence" => {
        "amount" => (1000 + index).to_s, "direction" => "支払", "transaction_kind" => "通常支払", "merchant" => "比較店" },
      "category_name" => "未登録AI分類", "payment_method_name" => payment.name, "account_name" => account.name }
  end
  result = Gemini::ExtractionResult.success(items)
  Gemini::TransactionExtractor.define_singleton_method(:new) { |**_| Struct.new(:call).new(result) }
  session = ActionDispatch::Integration::Session.new(Rails.application)
  setup = { "screens" => 0, "form_submissions" => 0, "submitted_fields" => 0 }
  if mode == "after"
    setup_steps = [
      ["/payment_methods/#{payment.id}/edit", "/payment_methods/#{payment.id}", { payment_method: { import_kind: "bank" } }],
      ["/settings/edit", "/settings", { setting: { image_import_requires_approval: "0" } }],
      ["/import_sources/#{source.id}/edit", "/import_sources/#{source.id}", { import_source: { image_auto_apply_enabled: "1" } }]
    ]
    setup_steps.each do |get_path, update_path, params|
      session.get(get_path)
      raise "setup GET failed" unless session.response.status == 200
      setup["screens"] += 1
      session.patch(update_path, params: params)
      raise "setup PATCH failed" unless session.response.redirect?
      session.follow_redirect!
      raise "setup result failed" unless session.response.status == 200
      setup["screens"] += 1
      setup["form_submissions"] += 1
      setup["submitted_fields"] += params.values.first.size
    end
    session.get("/import_classification_rules/new")
    setup["screens"] += 1
    token = Nokogiri::HTML(session.response.body).at_css('input[name="token"]')["value"]
    values = { import_source_id: source.id, channel: "image", merchant_key: "比較店", direction: "expense",
      category_id: category.id, payment_method_id: payment.id, account_id: account.id,
      credit_card_status: "not_applicable", priority: "100", enabled: "1" }
    session.post("/import_classification_rules", params: { import_classification_rule: values, token: token, confirmed: "1" })
    raise "rule save failed" unless session.response.redirect? && ImportClassificationRule.where(import_source: source).count == 1
    session.follow_redirect!
    raise "rule result failed" unless session.response.status == 200
    setup["screens"] += 1
    setup["form_submissions"] += 1
    setup["submitted_fields"] += values.size + 1
  else
    Setting.current.update!(image_import_requires_approval: true)
  end

  metrics = { "transaction_form_inputs" => 0, "reselected_fields" => 0, "file_acquisitions" => 0,
    "uploads" => 0, "normal_approvals" => 0, "screens" => 0, "source_selections" => 0 }
  session.get("/image_imports/new")
  raise "upload page failed" unless session.response.status == 200
  metrics["screens"] += 1
  image = Rack::Test::UploadedFile.new(StringIO.new("fixed synthetic 10-item image"), "image/png", false, original_filename: "comparison.png")
  metrics["file_acquisitions"] += 1
  session.post("/image_imports", params: { import_source_id: source.id, images: [image] })
  metrics["uploads"] += 1
  metrics["source_selections"] += 1
  raise "upload failed" unless session.response.redirect?
  session.follow_redirect!
  raise "review failed" unless session.response.status == 200
  metrics["screens"] += 1
  documents = ImportDocument.where(import_source: source)
  drafts = ImageImportDraft.joins(:import_entry).where(import_entries: { import_document_id: documents.select(:id) }).order(:id)
  raise "10 drafts required" unless drafts.count == 10
  if mode == "before"
    page = Nokogiri::HTML(session.response.body)
    selected = page.css('input[type="checkbox"][name="draft_ids[]"]').map { |element| element["value"] }
    unless selected.size == 10
      File.write("/tmp/budget-book-68-validation/operations-before.html", session.response.body)
      raise "10 review forms required (#{selected.size})"
    end
    edits = drafts.to_h do |draft|
      raise "AI suggestion must be unresolved" unless draft.category_id.nil?
      metrics["transaction_form_inputs"] += 1
      metrics["reselected_fields"] += 1
      [draft.id.to_s, { category_id: category.id }]
    end
    metrics["normal_approvals"] = selected.size
    session.patch("/image_import_drafts/bulk_approve", params: { draft_ids: selected, drafts: edits, document_ids: documents.pluck(:id) })
    raise "approval failed" unless session.response.redirect?
    session.follow_redirect!
    metrics["screens"] += 1
  else
    raise "unexpected approval UI" if Nokogiri::HTML(session.response.body).at_css('input[name="draft_ids[]"]')
    raise "automatic summary missing" unless session.response.body.include?("自動反映 10件")
  end
  raise "10 transactions required" unless Transaction.where(account: account).count == 10
  File.write(output, JSON.pretty_generate({ mode: mode, metrics: metrics, initial_setup: setup, transactions: 10,
    total: Transaction.where(account: account).sum(:amount), image: "fixed synthetic 10-item image", extraction: "HTTP boundary stub; same payload before/after" }) + "\n")
  raise ActiveRecord::Rollback
end
