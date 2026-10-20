require "rails_helper"

RSpec.describe "import entry resolution", type: :request do
  let(:category) { Category.create!(name: "食費", kind: :expense) }
  let(:payment) { PaymentMethod.create!(name: "現金") }
  let(:account) { Account.create!(name: "財布", kind: :cash) }
  let(:draft) { tracked_draft(category: category, payment_method: payment, account: account, date: Date.new(2026, 9, 30), amount: 500, memo: "店") }

  it "月を跨いだ予定を比較表示し、差分をプレビューして同じIDを実績化する" do
    entry = draft.import_entry
    target = Transaction.create!(draft.transaction_attributes.merge(entry_type: :planned, date: Date.new(2026, 10, 1)))
    get import_entry_path(entry)
    expect(response.body).to include("取引 ##{target.id}", "予定", "まとめ入力: 未導入")
    post preview_import_entry_path(entry), params: { decision: "link", target_id: target.id, draft: { memo: "確認後" } }
    expect(response.body).to include("予定 → 実績", "確認する差分")
    token = Nokogiri::HTML(response.body).at_css('input[name="review_token"]')["value"]
    expect { patch resolve_import_entry_path(entry), params: { decision: "link", target_id: target.id, review_token: token } }.not_to change(Transaction, :count)
    expect(target.reload).to be_actual
    expect(target.memo).to eq("店")
    expect(entry.reload.state).to eq("linked")
  end

  it "削除確認済みの詳細・一覧は再確認欄を出さない" do
    entry = draft.import_entry
    Imports::Applier.call(entry_id: entry.id, action: "approve")
    Transaction.find(entry.reload.target_transaction_id).destroy!
    token = review_token(entry, "acknowledge_deleted")
    patch resolve_import_entry_path(entry), params: { decision: "acknowledge_deleted", review_token: token }
    get import_entry_path(entry)
    expect(response.body).to include("削除確認済み")
    expect(response.body).not_to include("候補を編集・判断")
    get image_import_drafts_path(document_ids: [entry.import_document_id])
    expect(entry.reload.state).to eq("deletion_acknowledged")
  end

  it "取込元未選択なら外部AIを呼ばず説明する" do
    expect(Gemini::TransactionExtractor).not_to receive(:new)
    image = Rack::Test::UploadedFile.new(StringIO.new("image"), "image/png", false, original_filename: "a.png")
    post image_imports_path, params: { images: [image] }
    follow_redirect!
    expect(response.body).to include("取込元を選択してください")
  end

  it "別取引プレビューに既存取引と未処理候補の比較snapshotを表示する" do
    entry = draft.import_entry
    other_category = Category.create!(name: "比較用カテゴリ", kind: :expense)
    target = Transaction.create!(draft.transaction_attributes.merge(category: other_category, memo: "比較する実績"))
    other = tracked_draft(account: account, payment_method: payment, category: other_category, date: draft.date, amount: draft.amount, memo: "比較する候補")
    post preview_import_entry_path(entry), params: { decision: "distinct" }
    expect(response.body).to include("比較する取引の内容", "比較する未処理候補の内容", "比較用カテゴリ", "現金", "クレカ支払状況")
    expect(response.body).to include("取引 ##{target.id}", "比較する実績", "比較する候補")
    expect(response.body).to include(import_entry_path(other.import_entry_id))
  end
end
