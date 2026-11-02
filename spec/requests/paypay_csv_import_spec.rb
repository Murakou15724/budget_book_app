require "rails_helper"
require_relative "../support/paypay_csv_fixtures"

RSpec.describe "PayPay CSV import", type: :request do
  before { setup_csv_source }

  def upload(bytes)
    file = Tempfile.new(["fictional", ".csv"])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/octet-stream")
  ensure
    @upload_files ||= []
    @upload_files << file
  end

  after { @upload_files&.each(&:close!) }

  def submit(bytes = csv_bytes, **params)
    post csv_imports_path, params: { source_id: @source.id, csv_file: upload(bytes) }.merge(params)
  end

  def form_pairs(html)
    form = Nokogiri::HTML(html).css("form").find { |node| node["action"].include?("bulk_approve") }
    expect(form).not_to be_nil
    pairs = form.css("input[name], select[name], textarea[name]").filter_map do |node|
      next if %w[submit button].include?(node["type"]) || node["disabled"]
      if node["type"] == "checkbox"
        next unless %w[draft_ids[] entry_ids[]].include?(node["name"]) || node["checked"]
      end
      value = if node.name == "select"
        option = node.at_css("option[selected]") || node.at_css("option")
        option && (option["value"] || option.text)
      elsif node.name == "textarea"
        node.text
      else
        node["value"].to_s
      end
      [node["name"], value]
    end
    [form["action"], pairs]
  end

  it "shows setup/limits/retention and imports valid rows without trusting MIME or client outputs" do
    get new_csv_imports_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("8MiB", "1,000行", "支払経路", "原文13列")
    submit(csv_bytes, payload: { amount: 1 }, action: "auto_apply")
    expect(response).to redirect_to(import_document_path(ImportDocument.last))
    follow_redirect!
    expect(response.body).to include("今回新たに自動反映した取引は1件", "CSV記載額", "累積結果", "000-AbC")
    expect(Transaction.last.amount).to eq(1000)
  end

  it "rejects entire malformed files with 422 and persists no header or valid-looking prefix" do
    baseline = [ImportDocument.count, ImportEntry.count, Transaction.count]
    ["", "\uFEFF", "\xFF".b, csv_bytes + "a,b\n", csv_bytes + '"unfinished', csv_bytes([], headers: ["不正"])].each do |bytes|
      submit(bytes)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("CSVが空です") if bytes.empty? || bytes == "\uFEFF"
      expect([ImportDocument.count, ImportEntry.count, Transaction.count]).to eq(baseline)
    end
    submit(csv_bytes([]))
    expect(response).to be_redirect
    expect(ImportDocument.last.import_entries.count).to eq(0)
  end

  it "rejects non-PayPay/legacy sources and multiple files, and enforces actual bytes over fake size" do
    other = ImportSource.create!(name: "その他", account: @bank, service_key: "other")
    submit(csv_bytes, source_id: other.id)
    expect(response).to have_http_status(:unprocessable_entity)
    post csv_imports_path, params: { source_id: @source.id, csv_file: [upload(csv_bytes), upload(csv_bytes)] }
    expect(response).to have_http_status(:unprocessable_entity)
    fake = StringIO.new("x" * (Imports::PaypayCsvParser::MAX_BYTES + 1))
    allow(fake).to receive(:size).and_return(1)
    result = Imports::CsvReceiver.call(source: @source, file: fake)
    expect(result.file_error.code).to eq("csv_too_large")
    expect(ImportDocument.count).to eq(0)
  end

  it "shows all raw fields and reasons safely, processes mixed valid/invalid/special rows, and resends without duplication" do
    rows = [csv_row, csv_row(取引番号: "bad", 取引日: "", 出金金額（円）: "1.2", 取引先: '<script>alert("x")</script>'), csv_row(取引番号: "held", 取引内容: "返金", 出金金額（円）: "30")]
    submit(csv_bytes(rows))
    document = ImportDocument.last
    follow_redirect!
    expect(response.body).to include("取引日時が欠落・不正", "円金額が整数", "返金")
    expect(response.body).not_to include('<script>alert("x")</script>')
    submit(csv_bytes(rows))
    expect(Transaction.count).to eq(1)
    bad = document.import_entries.find_by(row_number: 3)
    get import_entry_path(bad)
    expect(response.body).to include("&lt;script&gt;", "CSV論理行 3")
    expect(response.body).to include("取引方法", "取引番号")
  end

  it "paginates 1,000 rows and 100 candidates, submits actual encoded forms below the Rack parameter limit, and keeps filters" do
    Setting.current.update!(image_import_requires_approval: true)
    rows = 1000.times.map { |index| csv_row(取引番号: "page-#{index}", 出金金額（円）: (index + 1).to_s) }
    submit(csv_bytes(rows))
    document = ImportDocument.last
    expect(document.import_entries.count).to eq(1000)
    get import_document_path(document)
    expect(response.body.scan(/原文全文・差分を確認/).size).to eq(100)
    expect(response.body).to include("全 1000行", "次の100行")
    get import_document_path(document, page: 10)
    expect(response.body).to include("行1001:")
    filter = { document_ids: [document.id], filter: "pending", page: 1, candidate_page: 1, image_numbers: { document.id.to_s => [1] } }
    get image_import_drafts_path(filter)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("対象候補 1000件", "次の100候補")
    action, pairs = form_pairs(response.body)
    expect(pairs.count { |key, _| key == "draft_ids[]" }).to eq(100)
    expect(pairs.count { |key, _| key == "entry_ids[]" }).to eq(100)
    expect(pairs.length).to be < 4096
    expect(pairs.map(&:first).join).not_to include("csv_raw", "source_method")
    hidden = document.import_entries.order(:row_number).offset(100).first.image_import_draft
    expect(pairs.map(&:first)).not_to include("drafts[#{hidden.id}][amount]")
    preview_pairs = pairs.reject { |key, _| %w[_method date].include?(key) } + [["date", "2026-11-01"], ["_method", "post"]]
    post preview_import_draft_dates_path, params: URI.encode_www_form(preview_pairs), headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("日付の一括指定 100件")
    patch action, params: URI.encode_www_form(pairs), headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
    expect(response).to be_redirect
    expect(URI.decode_www_form(URI.parse(response.location).query).to_h).to include("candidate_page" => "1", "filter" => "pending", "page" => "1")
    expect(Transaction.count).to eq(100)
    expect(hidden.import_entry.reload).not_to be_terminal
    get image_import_drafts_path(filter.merge(candidate_page: 99))
    expect(response.body).to include("候補ページ 9 / 9")
    expect(response.body.scan(/この候補を登録する/).size).to eq(100)
    get import_documents_path
    expect(response.body).to include("解析完了 1000行")
    expect(response.body).not_to include("page-999", "原文全文・差分を確認")
  end

  it "rejects bulk invalid/101 unique IDs before any updates and rejects only the displayed page" do
    Setting.current.update!(image_import_requires_approval: true)
    result = receive_csv(101.times.map { |index| csv_row(取引番号: "bulk-#{index}", 出金金額（円）: (index + 1).to_s) })
    ids = result.document.import_entries.order(:id).map { |entry| entry.image_import_draft.id }
    [[bulk_approve_image_import_drafts_path, :patch], [bulk_reject_image_import_drafts_path, :delete]].each do |path, verb|
      public_send(verb, path, params: { draft_ids: ids })
      expect(response).to have_http_status(:unprocessable_entity)
      public_send(verb, path, params: { draft_ids: ["invalid"] })
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(Transaction.count).to eq(0)
    expect(result.document.import_entries.where(state: "rejected").count).to eq(0)
    delete bulk_reject_image_import_drafts_path, params: { draft_ids: ids.first(100), document_ids: [result.document.id], candidate_page: 1 }
    expect(response).to be_redirect
    expect(result.document.import_entries.where(state: "rejected").count).to eq(100)
    expect(result.document.import_entries.order(:id).last.state).not_to eq("rejected")
  end

  it "requires explicit route confirmation and returns validation/stale/immutable errors with 422" do
    path = import_source_import_payment_routes_path(@source)
    values = { source_method: "新規現金", account_id: @bank.id, payment_method_id: @csv_routes["架空銀行"].payment_method_id, credit_card_status: "not_applicable", enabled: "1" }
    post path, params: { import_payment_route: values }
    expect(response).to have_http_status(:unprocessable_entity)
    post path, params: { import_payment_route: values, confirmed: "1" }
    expect(response).to redirect_to(path)
    route = ImportPaymentRoute.last
    stale_version = route.lock_version
    route.update!(enabled: false)
    patch import_source_import_payment_route_path(@source, route), params: { import_payment_route: { lock_version: stale_version, enabled: true }, confirmed: "1" }
    expect(response).to have_http_status(:unprocessable_entity)
    patch import_source_import_payment_route_path(@source, route), params: { import_payment_route: { source_method: "改変" }, confirmed: "1" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(route.reload.source_method).to eq("新規現金")
    get new_import_classification_rule_path
    expect(response.body).to include("PayPay CSV", "CSV支払経路")
  end

  it "renders histories and full raw details with a near-8MiB ID without sorting the large JSON payload" do
    base = csv_bytes([csv_row(取引番号: "x")])
    identifier = "0" * (Imports::PaypayCsvParser::MAX_BYTES - base.bytesize + 1)
    submit(csv_bytes([csv_row(取引番号: identifier)]))
    expect(response).to be_redirect
    document = ImportDocument.last
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("解析完了 1行")
    get import_documents_path
    expect(response).to have_http_status(:ok)
    get image_import_drafts_path(document_ids: [document.id])
    expect(response).to have_http_status(:ok)
    entry_id = document.import_entries.pick(:id)
    get import_entry_path(entry_id)
    expect(response).to have_http_status(:ok)
    expect(response.body.include?(identifier)).to be(true)
  end

  it "imports ten configured payments and income via HTTP onto their individual routes and requires no per-row selections" do
    bytes = File.binread(Rails.root.join("spec/fixtures/files/paypay_csv/configured_ten.csv"))
    submit(bytes)
    expect(response).to be_redirect
    expect(Transaction.count).to eq(10)
    document = ImportDocument.last
    document.import_entries.includes(:target_transaction).each do |entry|
      route = @csv_routes.fetch(entry.payload["source_method"])
      expect(entry.target_transaction.attributes.slice(*ImportPaymentRoute::OUTPUT_KEYS)).to eq(route.attributes.slice(*ImportPaymentRoute::OUTPUT_KEYS))
    end
    follow_redirect!
    expect(response.body).to include("今回新たに自動反映した取引は10件")
    submit(bytes)
    expect(Transaction.count).to eq(10)
  end

  it "keeps all ten configured rows pending when approval is required and does not replay them after settings change" do
    Setting.current.update!(image_import_requires_approval: true)
    bytes = File.binread(Rails.root.join("spec/fixtures/files/paypay_csv/configured_ten.csv"))
    submit(bytes)
    expect(response).to be_redirect
    expect(Transaction.count).to eq(0)
    document = ImportDocument.last
    expect(document.import_entries.count).to eq(10)
    expect(document.import_entries.where(state: %w[pending held]).count).to eq(10)
    follow_redirect!
    expect(response.body).to include("承認待ち・要確認", "今回新たに自動反映した取引は0件")
    Setting.current.update!(image_import_requires_approval: false)
    submit(bytes)
    expect(Transaction.count).to eq(0)
    ids = document.import_entries.order(:id).limit(3).pluck(:id)
    post preview_import_draft_dates_path, params: { entry_ids: ids, date: "2026-11-01" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("識別用元口座", "反映口座", "取引方法", @bank.name, @wallet.name, @card.name, "PayPayクレジット")
  end

  it "honors the approval and CSV permission matrix through HTTP independently of image permission" do
    [[true, true], [true, false], [false, false], [false, true]].each_with_index do |(approval, enabled), index|
      Setting.current.update!(image_import_requires_approval: approval)
      @source.update!(csv_auto_apply_enabled: enabled, image_auto_apply_enabled: !enabled)
      before_count = Transaction.count
      submit(csv_bytes([csv_row(取引番号: "http-gate-#{index}", 出金金額（円）: (30 + index).to_s)]))
      expect(response).to be_redirect
      expect(Transaction.count - before_count).to eq(!approval && enabled ? 1 : 0)
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end
  end

  it "reports a candidate-save failure with rollback and retries the same file without duplicate valid rows" do
    calls = 0
    allow(Imports::EntryRecorder).to receive(:call).and_wrap_original do |original, **args|
      calls += 1
      raise "fictional write failure" if calls == 2
      original.call(**args)
    end
    bytes = csv_bytes([csv_row, csv_row(取引番号: "http-second", 出金金額（円）: "2")])
    submit(bytes)
    expect(response).to be_redirect
    document = ImportDocument.last
    expect(document.state).to eq("failed")
    expect(document.import_entries.count).to eq(0)
    expect(Transaction.count).to eq(0)
    follow_redirect!
    expect(response.body).to include("処理に失敗した行があります", "解析失敗", "履歴")
    allow(Imports::EntryRecorder).to receive(:call).and_call_original
    submit(bytes)
    expect(ImportDocument.count).to eq(1)
    expect(Transaction.count).to eq(2)
  end

  it "reports automatic partial failure in the result screen, continues other rows, and preserves committed rows on resend" do
    calls = 0
    allow(Imports::Applier).to receive(:call).and_wrap_original do |original, **args|
      calls += 1
      raise "fictional automatic failure" if calls == 1
      original.call(**args)
    end
    bytes = csv_bytes([csv_row, csv_row(取引番号: "http-second", 出金金額（円）: "2")])
    submit(bytes)
    expect(response).to be_redirect
    document = ImportDocument.last
    expect(document.state).to eq("extracted")
    expect(Transaction.count).to eq(1)
    failed = document.import_entries.find_by(row_number: 2)
    expect(failed.import_events.where(kind: "processing_failed").count).to eq(1)
    follow_redirect!
    expect(response.body).to include("処理に失敗した行があります", "今回新たに自動反映した取引は1件", "エラー")
    submit(bytes)
    expect(Transaction.count).to eq(1)
    expect(calls).to eq(2)
  end
end
