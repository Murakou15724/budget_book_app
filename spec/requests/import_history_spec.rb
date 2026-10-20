require "rails_helper"

RSpec.describe "import history", type: :request do
  it "処理済み文書が50件増えても古い未処理候補を通常レビューに表示する" do
    pending = tracked_draft(amount: 500)
    source = pending.import_entry.import_document.import_source
    50.times { import_document(source: source, state: "extracted") }
    get image_import_drafts_path
    expect(response.body).to include(import_entry_path(pending.import_entry_id))
    expect(response.body).not_to include("レビュー待ちの候補はありません")
  end

  it "指定した51文書すべてへページ送りで到達できる" do
    source = import_document.import_source
    documents = 51.times.map { import_document(source: source, state: "extracted") }
    document_ids = documents.map(&:id)
    get image_import_drafts_path(document_ids: document_ids)
    page = Nokogiri::HTML(response.body)
    expect(page.css("section.entry-card").size).to eq(50)
    next_link = page.css("a").find { |a| a.text == "次の50文書" }
    expect(next_link).to be_present
    get next_link["href"]
    page = Nokogiri::HTML(response.body)
    expect(page.css("section.entry-card").size).to eq(1)
    expect(response.body).to include("取込文書 ##{documents.last.id}", "前の50文書")
    expect(response.body).not_to include("取込文書 ##{documents.first.id}<")
  end
  it "処理済み・却下済みでも出所・元候補・理由・歴史取引IDを辿れる" do
    account = Account.create!(name: "履歴口座", kind: :bank)
    category = Category.create!(name: "食費", kind: :expense)
    payment = PaymentMethod.create!(name: "現金")
    draft = tracked_draft(account: account, category: category, payment_method: payment,
      date: Date.new(2026, 10, 1), amount: 500, direction: :expense, memo: "履歴テスト")
    entry = draft.import_entry
    Imports::Applier.call(entry_id: entry.id, action: "approve")
    get import_document_path(entry.import_document)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("履歴口座", "反映済", "対応取引", "SHA-256")
    get image_import_drafts_path(document_ids: [entry.import_document_id])
    expect(response.body).to include("レビュー待ちの候補はありません", "反映済")
    get import_entry_path(entry)
    expect(response.body).to include("履歴テスト", "処理履歴")
    expect(response.body).not_to include("候補を編集・判断")
  end

  it "0行成功・失敗・未完了を区別し、batchと文書フィルタを維持する" do
    success = import_document(state: "extracted", batch_id: "batch-ok")
    failure = import_document(state: "failed", error_code: "extraction_failed")
    received = import_document
    get image_import_drafts_path(document_ids: [success.id, failure.id, received.id])
    expect(response.body).to include("解析完了 0行", "解析失敗", "解析未完了", "取引行数不明")
    get image_import_drafts_path(batch_id: "batch-ok")
    expect(response.body).to include("解析完了 0行")
    expect(response.body).not_to include("解析失敗")
  end

  it "一覧の解析状態・元口座・日付絞り込みができる" do
    document = import_document(state: "failed", received_at: Time.zone.local(2026, 10, 1))
    get import_documents_path(state: "failed", source_id: document.import_source_id, from_date: "2026-10-01", to_date: "2026-10-01")
    expect(response.body).to include("取込文書 ##{document.id}")
  end

  it "取込元は初回設定後に再利用でき、HTTP経由で識別情報を変更できない" do
    account = Account.create!(name: "元口座", kind: :bank)
    post import_sources_path, params: { import_source: { name: "サービス", service_key: "service", account_id: account.id } }
    source = ImportSource.last
    patch import_source_path(source), params: { import_source: { name: "新表示名", service_key: "changed", account_id: nil } }
    expect(source.reload.name).to eq("新表示名")
    expect(source.service_key).to eq("service")
    get new_image_imports_path
    expect(response.body).to include("新表示名", "元口座")
  end

  it "文書で絞り込んだ一覧の個別却下でも対象文書を維持する" do
    first = tracked_draft(amount: 500)
    second = tracked_draft(amount: 600)
    unrelated = tracked_draft(amount: 700)
    document_ids = [first, second].map { |draft| draft.import_entry.import_document_id }
    numbers = { document_ids[0].to_s => [1], document_ids[1].to_s => [3] }
    get image_import_drafts_path(document_ids: document_ids, image_numbers: numbers)
    page = Nokogiri::HTML(response.body)
    link = page.at_css("a[href^='/image_import_drafts/#{first.id}?']")
    expect(link).to be_present
    delete link["href"]
    follow_redirect!
    expect(response.body).to include("取込文書 ##{document_ids[0]}", "取込文書 ##{document_ids[1]}", "画像3")
    expect(response.body).not_to include("取込文書 ##{unrelated.import_entry.import_document_id}")
    expect(first.import_entry.reload.state).to eq("rejected")
  end

  it "新規・重複・訂正・保留を排他的に集計する" do
    document = import_document(state: "extracted")
    representative_document = import_document(source: document.import_source, state: "extracted")
    representative = tracked_draft(document: representative_document, amount: 100, trusted_external_id: "id", payload: { amount: 100 }).import_entry
    Imports::Applier.call(entry_id: representative.id, action: "reject")
    tracked_draft(document: document, amount: 100, trusted_external_id: "id", payload: { amount: 100 })
    tracked_draft(document: document, amount: 200)
    correction = tracked_draft(document: document, amount: 300).import_entry
    correction.update!(classification: "correction", state: "held", reason_code: "external_id_changed")
    hold = tracked_draft(document: document, amount: 400).import_entry
    hold.update!(classification: "hold", state: "held", reason_code: "user_held")
    get import_document_path(document)
    text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")
    expect(text).to include("新規 1件 / 重複 1件 / 訂正 1件 / 保留 1件")
  end
end
