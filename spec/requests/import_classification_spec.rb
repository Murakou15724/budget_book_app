require "rails_helper"

RSpec.describe "取込分類の画面とHTTP境界", type: :request do
  let!(:account) { Account.create!(name: "HTTP元", kind: :bank) }
  let!(:category) { Category.create!(name: "HTTP費", kind: :expense) }
  let!(:payment) { PaymentMethod.create!(name: "HTTP銀行", import_kind: "bank") }
  let(:draft) { tracked_draft(account: account, category: category, payment_method: payment, date: Date.new(2026, 10, 1), amount: 1000, payload: extraction_payload) }

  it "HTTPからauto_apply・内部metadataを注入できない" do
    entry = draft.import_entry
    patch resolve_import_entry_path(entry), params: { decision: "auto_apply" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Transaction.count).to eq(0)
    post preview_import_entry_path(entry), params: { decision: "distinct", draft: { date_origin: "source",
      confirmation_metadata: { version: 99 }, rule_decision: { matched_rules: [1] } } }
    expect(draft.reload.date_origin).to eq("user")
    expect(draft.confirmation_metadata["version"]).to eq(1)
    expect(draft.rule_decision).to eq({})
  end

  it "アップロード時のmanual_dateを422で案内しAIを呼ばない" do
    expect(Gemini::TransactionExtractor).not_to receive(:new)
    post image_imports_path, params: { manual_date: "2026-10-01" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("抽出後")
  end

  it "日付一括指定は対象・元口座・店・旧日付と新日付を表示して確定する" do
    entry = draft.import_entry
    post preview_import_draft_dates_path, params: { entry_ids: [entry.id], date: "2026-10-08" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("HTTP元", "店", "2026-10-01", "2026-10-08")
    expect(draft.reload.date).to eq(Date.new(2026, 10, 1))
    token = Nokogiri::HTML(response.body).at_css('input[name="token"]')["value"]
    patch import_draft_dates_path, params: { token: token }
    expect(response.body).to include("自動登録は行いません")
    expect(draft.reload.date).to eq(Date.new(2026, 10, 8))
    expect(Transaction.count).to eq(0)
    count = ImportEvent.count
    patch import_draft_dates_path, params: { token: token }
    expect(response.body).to include("保存済みの日付指定結果", "2026-10-08")
    expect(response.body).not_to include("全対象の日付を確定")
    expect(ImportEvent.count).to eq(count)
  end

  it "カード引落由来の候補に既存クレカ未払い一覧への案内を表示する" do
    draft.update!(transaction_kind: "card_settlement", confirmation_metadata: { "version" => 1, "source_kind" => "card_settlement" })
    get import_entry_path(draft.import_entry_id)
    expect(response.body).to include(credit_card_unpaids_path, "クレカ未払い一覧で対応する取引を確認")
  end

  it "日付一括previewの不正日付・存在しないID・処理済み混入・上限超過を422で無更新にする" do
    entry = draft.import_entry
    cases = [ { entry_ids: [entry.id], date: "2026-02-30" },
      { entry_ids: [entry.id, 999999999], date: "2026-10-05" },
      { entry_ids: (1..101).to_a, date: "2026-10-05" } ]
    cases.each do |values|
      before = [draft.reload.attributes, entry.reload.attributes, ImportEvent.count]
      post preview_import_draft_dates_path, params: values
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("変更していません")
      expect([draft.reload.attributes, entry.reload.attributes, ImportEvent.count]).to eq(before)
    end
    entry.update!(state: "rejected")
    before = [draft.reload.attributes, entry.reload.attributes, ImportEvent.count]
    post preview_import_draft_dates_path, params: { entry_ids: [entry.id], date: "2026-10-05" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect([draft.reload.attributes, entry.reload.attributes, ImportEvent.count]).to eq(before)
  end

  it "確認済み履歴からの作成リンクとルールの範囲・優先順位を表示する" do
    entry = draft.import_entry
    Imports::Applier.call(entry_id: entry.id, action: "approve")
    get import_entry_path(entry)
    expect(response.body).to include("この確認内容からルールを作る", "対応実績を訂正する")
    get new_import_classification_rule_path(entry_id: entry.id)
    expect(response.body).to include("今後再利用する", "元口座", "優先順位")
    expect(response.body).not_to match(/name="confirmed"[^>]*checked/)
    token = Nokogiri::HTML(response.body).at_css('input[name="token"]')["value"]
    values = { import_source_id: entry.import_document.import_source_id, channel: "image", merchant_key: "店", direction: "expense",
      category_id: category.id, payment_method_id: payment.id, account_id: account.id, credit_card_status: "not_applicable", priority: 10, enabled: "1" }
    expect { post import_classification_rules_path, params: { import_classification_rule: values, token: token, confirmed: "1" } }.to change(ImportClassificationRule, :count).by(1)
    follow_redirect!
    expect(response.body).to include("HTTP元", "10", "version", "確認済み")
  end

  it "移動先参照だけを持つ未処理・処理済み・却下済み候補でも口座削除を拒否する" do
    target = Account.create!(name: "移動先だけ", kind: :cash)
    draft.update!(to_account: target)
    %w[pending applied rejected].each do |state|
      draft.import_entry.update!(state: state)
      expect { delete account_path(target) }.not_to change(Account, :count)
      follow_redirect!
      expect(response.body).to include("削除")
      expect(draft.reload.to_account_id).to eq(target.id)
    end
  end

  it "全件自動反映済みでも方向別金額とルールsnapshotを表示する" do
    source = draft.import_entry.import_document.import_source
    rule = confirmed_rule(source: source, category: category, payment: payment)
    source.update!(image_auto_apply_enabled: true)
    Setting.current.update!(image_import_requires_approval: false)
    document = import_document(source: source, state: "extracted")
    generated = ImageImportDraftBuilder.build([extraction_payload(amount: 2200)], document: document).last.first
    expect(Imports::Applier.call(entry_id: generated.import_entry_id, action: "auto_apply").status).to eq(:applied)
    rule.update!(merchant_key: "変更後", enabled: false)
    get image_import_drafts_path(document_ids: [document.id])
    expect(response.body).to include("自動反映 1件", "2200円", "店", "個別承認は不要")
    expect(response.body).not_to include("この候補を登録する")
  end

  it "不正予定の保留理由と対象の修正リンクを返し、予定・候補・イベントを無変更にする" do
    entry = draft.import_entry
    cash = PaymentMethod.create!(name: "誤った現金経路", import_kind: "cash")
    target = Transaction.create!(draft.transaction_attributes.merge(payment_method: cash, entry_type: "planned"))
    post preview_import_entry_path(entry), params: { decision: "link", target_id: target.id }
    token = Nokogiri::HTML(response.body).at_css('input[name="review_token"]')["value"]
    before = [draft.reload.attributes, entry.reload.attributes, target.reload.attributes, ImportEvent.count]
    patch resolve_import_entry_path(entry), params: { decision: "link", target_id: target.id, review_token: token }
    follow_redirect!
    expect(response.body).to include("支払方法・口座・クレカ状態が一致しません", "対象予定 ##{target.id} を修正する", edit_transaction_path(target))
    expect([draft.reload.attributes, entry.reload.attributes, target.reload.attributes, ImportEvent.count]).to eq(before)
  end

  it "非クレカ候補の一覧日付変更で旧支払予定日を持ち込まず登録する" do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
    get image_import_drafts_path(document_ids: [draft.import_entry.import_document_id])
    expect(response.body).not_to include("name=\"drafts[#{draft.id}][credit_card_payment_due_on_override]\"")
    old_due = draft.calculated_credit_card_payment_due_on
    patch bulk_approve_image_import_drafts_path, params: { draft_ids: [draft.id], drafts: {
      draft.id.to_s => { date: "2026-10-20", credit_card_payment_due_on_override: old_due.iso8601 } } }
    expect(draft.reload.import_entry.state).to eq("applied")
    target = Transaction.find(draft.import_entry.target_transaction_id)
    expect(target.date).to eq(Date.new(2026, 10, 20))
    expect(target.credit_card_payment_due_on_override).to be_nil
  end
end
