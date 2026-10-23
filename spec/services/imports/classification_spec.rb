require "rails_helper"

RSpec.describe "取込分類・自動反映の境界" do
  let!(:account) { Account.create!(name: "分類元", kind: :bank) }
  let!(:category) { Category.create!(name: "分類費", kind: :expense) }
  let!(:payment) { PaymentMethod.create!(name: "分類銀行", import_kind: "bank") }
  let(:source) { import_document(account: account).import_source }
  let(:document) { import_document(source: source) }

  def build(payload = extraction_payload, doc: document)
    ImageImportDraftBuilder.build([payload], document: doc).last.first
  end

  def auto(draft)
    Imports::Applier.call(entry_id: draft.import_entry_id, action: "auto_apply")
  end

  def enable
    Setting.current.update!(image_import_requires_approval: false)
    source.update!(image_auto_apply_enabled: true)
    confirmed_rule(source: source, category: category, payment: payment)
  end

  it "全角・空白・大文字だけを正規化し支店名や記号を維持する" do
    expect(Imports::MerchantKey.normalize("　ＳＨＯＰ\t 東京店　")).to eq("shop 東京店")
    expect(Imports::MerchantKey.normalize("SHOP-東京店")).to eq("shop-東京店")
    expect(Imports::MerchantKey.normalize("a" * 256)).to be_nil
    expect(Imports::MerchantKey.normalize(nil)).to be_nil
  end

  ["2024-02-29", "2024/2/29", "2024年2月29日"].each do |raw|
    it "原文の完全日付 #{raw} を厳密に解釈する" do
      expect(Imports::StrictDate.source(extraction_payload(date: "2024-02-29", raw_date: raw))).to eq(Date.new(2024, 2, 29))
    end
  end

  ["2月29日", "昨日", "2023-02-29", "2024-02-29〜2024-03-01", "1900-01-01", "2100-01-01"].each do |raw|
    it "不明・不正・範囲外の日付 #{raw} は補完しない" do
      expect(Imports::StrictDate.source(extraction_payload(raw_date: raw))).to be_nil
    end
  end

  it "日付の年なし・不確実・ISO不一致は未確定にする" do
    [extraction_payload(date_year_explicit: false), extraction_payload(uncertain_fields: ["date"]),
      extraction_payload(raw_date: "2026年10月2日")].each do |payload|
      expect(Imports::StrictDate.source(payload)).to be_nil
    end
  end

  it "元口座・source・収支・経路・取引先の完全一致だけを使う" do
    enable
    other = import_document(account: account).import_source
    other_bank = Account.create!(name: "別分類口座", kind: :bank)
    third = import_document(account: other_bank).import_source
    [other, third].each { |s| confirmed_rule(source: s, category: category, payment: payment) }
    draft = build
    expect(draft.rule_decision["matched_rules"].size).to eq(1)
    expect(draft.rule_decision["matched_rules"].first["import_source_id"]).to eq(source.id)
    expect(build(extraction_payload(merchant: "店 支店"), doc: import_document(source: source)).rule_decision["reason_codes"]).to include("rule_missing")
    expect(build(extraction_payload(direction: "income"), doc: import_document(source: source)).rule_decision["reason_codes"]).to include("rule_missing")
  end

  it "優先順位が異なり出力が同じでも複数一致は保留する" do
    enable
    confirmed_rule(source: source, category: category, payment: payment, priority: 1)
    draft = build
    expect(draft.rule_decision["matched_rules"].map { |r| r["priority"] }).to eq([1, 100])
    expect(draft.rule_decision["reason_codes"]).to include("rule_ambiguous")
    expect { expect(auto(draft).status).to eq(:held) }.not_to change(Transaction, :count)
  end

  [true, false].product([true, false]).each do |approval, source_enabled|
    it "承認必須=#{approval}・取込元許可=#{source_enabled} の両設定を適用する" do
      Setting.current.update!(image_import_requires_approval: approval)
      source.update!(image_auto_apply_enabled: source_enabled)
      confirmed_rule(source: source, category: category, payment: payment)
      draft = build
      expected = !approval && source_enabled ? :applied : :held
      expect(auto(draft).status).to eq(expected)
      expect(Transaction.count).to eq(expected == :applied ? 1 : 0)
    end
  end

  it "停止後の自動反映と設定ON後の遡及反映を阻止する" do
    rule = enable
    draft = build
    rule.update!(enabled: false)
    expect(auto(draft).status).to eq(:held)
    expect(draft.reload.rule_decision["reason_codes"]).to include("rule_changed")
    rule.update!(enabled: true)
    source.update!(image_auto_apply_enabled: false)
    later = build(extraction_payload(amount: 2000), doc: import_document(source: source))
    source.update!(image_auto_apply_enabled: true)
    expect(auto(later).status).to eq(:held)
    expect(Transaction.count).to eq(0)
  end

  it "名称提案がすべて一致しても旧schemaの根拠不足を自動確定しない" do
    enable
    payload = { "date" => "2026-10-01", "amount" => 1000, "direction" => "expense",
      "category_name" => category.name, "payment_method_name" => payment.name, "account_name" => account.name }
    draft = build(payload)
    expect(draft.date).to be_nil
    expect(draft.rule_decision["reason_codes"]).to include("date_unresolved", "extraction_evidence_missing")
    expect(auto(draft).status).to eq(:held)
  end

  it "正常行と収支不明行を同じ文書に保持し支出へ丸めない" do
    enable
    drafts = ImageImportDraftBuilder.build([extraction_payload, extraction_payload(direction: "unknown", amount: "1.5")], document: document).last
    expect(drafts.map(&:direction)).to eq(["expense", nil])
    expect(drafts.last.amount).to be_nil
    expect(drafts.last.import_entry.payload["amount"]).to eq("1.5")
    expect(auto(drafts.last).status).to eq(:held)
  end

  { "チャージ" => "charge", "振替" => "transfer", "カード引落" => "card_settlement", "返金" => "refund",
    "取消" => "cancellation", "手数料" => "fee" }.each do |word, kind|
    it "原文の#{word}をnormalから区別する" do
      enable
      draft = build(extraction_payload(memo: word))
      expect(draft.transaction_kind).to eq(kind)
      expect(auto(draft).status).to eq(:held)
      expect(Transaction.count).to eq(0)
    end
  end

  it "自動反映10件を個別承認せず確定イベントから集計でき、再実行とルール変更でも不変" do
    rule = enable
    drafts = ImageImportDraftBuilder.build(10.times.map { |i| extraction_payload(amount: 1000 + i) }, document: document).last
    drafts.each { |draft| expect(auto(draft).status).to eq(:applied) }
    before = Transaction.order(:id).map(&:attributes)
    events = document.import_events.where(kind: "applied").to_a
    expect(events.map { |e| e.details["mode"] }.uniq).to eq(["automatic"])
    expect(events.sum { |e| e.details["amount"] }).to eq(10_045)
    rule.update!(enabled: false)
    expect { drafts.each { |draft| auto(draft) } }.not_to change(Transaction, :count)
    expect(Transaction.order(:id).map(&:attributes)).to eq(before)
    expect(events.first.details.dig("rule_decision", "matched_rules").first["enabled"]).to be true
  end

  it "カテゴリ・口座・支払方法の不整合と不正amountをmanualでも拒否する" do
    draft = tracked_draft(account: account, category: category, payment_method: payment, date: Date.new(2026, 10, 1), amount: 1000)
    category.update!(kind: :income)
    expect(Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve").status).to eq(:held)
    expect(Transaction.count).to eq(0)
    category.update!(kind: :expense)
    payment.update!(import_kind: "cash")
    expect(Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve").status).to eq(:held)
    payment.update!(import_kind: "bank")
    ["1.2", "1e3", "-1"].each do |amount|
      expect(Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve", attributes: { amount: amount }).status).to eq(:failed)
    end
    expect(Transaction.count).to eq(0)
  end

  it "不正な予定へのlinkは候補・予定・イベントを変更しない" do
    draft = tracked_draft(account: account, category: category, payment_method: payment, date: Date.new(2026, 10, 1), amount: 1000)
    target = Transaction.create!(draft.transaction_attributes.merge(entry_type: "planned"))
    category.update!(kind: :income)
    entry = draft.import_entry
    token = review_token(entry, "link", target)
    before = [draft.reload.attributes, target.reload.attributes, entry.reload.attributes, ImportEvent.count]
    result = Imports::Applier.call(entry_id: entry.id, action: "link", target_id: target.id, review_token: token)
    expect(result.reason).to eq("invalid_planned_target")
    expect([draft.reload.attributes, target.reload.attributes, entry.reload.attributes, ImportEvent.count]).to eq(before)
    category.update!(kind: :expense)
    fresh = review_token(entry, "link", target)
    expect(Imports::Applier.call(entry_id: entry.id, action: "link", target_id: target.id, review_token: fresh).status).to eq(:linked)
    expect(target.reload).to be_actual
  end

  it "日付変更と不正金額の同時送信に失敗しても原文日付・出典を維持し、再送の有効な日付はuserになる" do
    enable
    draft = build
    before = draft.attributes
    result = Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve", attributes: { date: "2026-10-02", amount: "-1" })
    expect(result.status).to eq(:failed)
    expect(draft.reload.attributes).to eq(before)
    expect(draft.date_origin).to eq("source")
    expect(draft.confirmation_metadata["edited_at"]).to be_nil
    result = Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve", attributes: { date: "2026-10-02", amount: "1000" })
    expect(result.status).to eq(:applied)
    expect(draft.reload.date_origin).to eq("user")
    expect(draft.confirmation_metadata["edited_at"]).to be_present
    expect(draft.import_entry.payload["raw_date"]).to eq("2026-10-01")
  end
end
