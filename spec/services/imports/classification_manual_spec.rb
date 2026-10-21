require "rails_helper"

RSpec.describe "取込の手動種別と予定実績化" do
  let!(:account) { Account.create!(name: "手動元", kind: :bank) }
  let!(:destination) { Account.create!(name: "手動先", kind: :cash) }
  let!(:category) { Category.create!(name: "手動費", kind: :expense) }
  let!(:payment) { PaymentMethod.create!(name: "手動銀行", import_kind: "bank") }
  let(:draft) { tracked_draft(account: account, category: category, payment_method: payment, date: Date.new(2026, 10, 1), amount: 1000) }

  def link(target)
    entry = draft.import_entry
    token = review_token(entry, "link", target)
    before = [draft.reload.attributes, target.reload.attributes, entry.reload.attributes, ImportEvent.count]
    result = Imports::Applier.call(entry_id: entry.id, action: "link", target_id: target.id, review_token: token)
    [result, before, [draft.reload.attributes, target.reload.attributes, entry.reload.attributes, ImportEvent.count]]
  end

  it "チャージ由来でも利用者が移動種別・移動先・経路を明示すれば手動登録できる" do
    draft.update!(confirmation_metadata: { "version" => 1, "source_kind" => "charge" })
    result = Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve", attributes: {
      direction: "transfer", transaction_kind: "transfer", to_account_id: destination.id, category_id: nil })
    expect(result.status).to eq(:applied)
    target = Transaction.find(result.entry.target_transaction_id)
    expect(target).to be_transfer
    expect(target.category).to be_nil
    expect(target.to_account_id).to eq(destination.id)
    expect(draft.reload.confirmation_metadata["source_kind"]).to eq("charge")
  end

  it "移動先欠落・種別と収支の不一致は手動でも拒否する" do
    [ { direction: "transfer", transaction_kind: "transfer", category_id: nil },
      { direction: "expense", transaction_kind: "transfer", to_account_id: destination.id } ].each do |attributes|
      expect(Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve", attributes: attributes).status).to eq(:held)
    end
    expect(Transaction.count).to eq(0)
  end

  it "手数料は確認済みの支出だけ手動登録できる" do
    draft.update!(transaction_kind: "fee", confirmation_metadata: { "version" => 1, "source_kind" => "fee" })
    expect(Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve").status).to eq(:applied)
    expect(Transaction.last).to be_expense
    expect(ImportClassificationRule.count).to eq(0)
  end

  it "特殊からnormalへの種別訂正には専用チェックと理由の両方を要求する" do
    draft.update!(confirmation_metadata: { "version" => 1, "source_kind" => "refund" })
    [ {}, { kind_correction: "1" }, { kind_correction_reason: "原文誤読" } ].each do |confirmation|
      expect(Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve", confirmation: confirmation).status).to eq(:held)
    end
    expect(Transaction.count).to eq(0)
    expect(Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve", confirmation: {
      kind_correction: "1", kind_correction_reason: "原文誤読を確認" }).status).to eq(:applied)
    expect(Imports::RuleWriter.eligible?(draft.import_entry.reload)).to be false
  end

  %w[card_settlement refund cancellation].product(%w[fee transfer investment], %w[approve distinct adopt_revision]).each do |origin, kind, action|
    it "#{origin}由来を#{kind}にしても#{action}から新規登録しない" do
      document = import_document(account: account, state: "extracted")
      if action == "adopt_revision"
        tracked_draft(document: document, account: account, category: category, payment_method: payment,
          date: Date.new(2026, 10, 1), amount: 900, trusted_external_id: "special-revision", payload: extraction_payload(amount: 900))
      end
      candidate = tracked_draft(document: document, account: account, category: category, payment_method: payment,
        date: Date.new(2026, 10, 1), amount: 1000, payload: extraction_payload(transaction_kind: origin),
        trusted_external_id: action == "adopt_revision" ? "special-revision" : nil,
        confirmation_metadata: { "version" => 1, "source_kind" => origin })
      values = { transaction_kind: kind, direction: kind == "fee" ? "expense" : kind,
        category_id: kind == "fee" ? category.id : nil, to_account_id: kind == "fee" ? nil : destination.id }
      options = {}
      if action == "approve"
        options[:attributes] = values
      else
        Imports::CandidateConfirmation.apply(candidate, attributes: values).save!
        options[:review_token] = review_token(candidate.import_entry, action)
      end
      count = Transaction.count
      result = Imports::Applier.call(entry_id: candidate.import_entry_id, action: action, **options)
      expect(result.status).to eq(:held)
      expect(result.reason).to eq("special_transaction")
      expect(Transaction.count).to eq(count)
      expect(candidate.reload.import_entry.target_transaction_id).to be_nil
      expect(candidate.confirmation_metadata["source_kind"]).to eq(origin)
      expect(candidate.import_entry.import_events.where(kind: "applied")).not_to exist
    end
  end

  %w[transfer investment].each do |direction|
    it "原文の移動を確認した#{direction}予定だけを同じIDで実績化する" do
      draft.update!(confirmation_metadata: { "version" => 1, "source_kind" => "transfer" })
      Imports::CandidateConfirmation.apply(draft, attributes: { direction: direction, transaction_kind: direction,
        category_id: nil, to_account_id: destination.id }).save!
      target = Transaction.create!(draft.transaction_attributes.merge(entry_type: "planned"))
      result, = link(target)
      expect(result.status).to eq(:linked)
      expect(target.reload).to be_actual
      expect(target.direction).to eq(direction)
    end
  end

  it "未確認の移動予定とカード引落由来の予定昇格を無更新で拒否する" do
    target = Transaction.create!(draft.transaction_attributes.merge(direction: "transfer", category: nil, to_account: destination, entry_type: "planned"))
    result, before, after = link(target)
    expect(result.reason_codes).to include("special_transaction")
    expect(after).to eq(before)
    draft.update!(confirmation_metadata: { "version" => 1, "source_kind" => "card_settlement" })
    Imports::CandidateConfirmation.apply(draft, attributes: { direction: "transfer", transaction_kind: "transfer", category_id: nil, to_account_id: destination.id }).save!
    result, before, after = link(target)
    expect(result.status).to eq(:held)
    expect(after).to eq(before)
  end

  %w[cash_bank paid_new missing_destination].each do |variant|
    it "予定自身の#{variant}不整合を検出し全データを無変更にする" do
      values = draft.transaction_attributes.merge("entry_type" => "planned")
      case variant
      when "cash_bank"
        values["payment_method_id"] = PaymentMethod.create!(name: "予定現金", import_kind: "cash").id
      when "paid_new"
        values["payment_method_id"] = PaymentMethod.create!(name: "予定カード", import_kind: "credit_card").id
        values["credit_card_status"] = "paid"
      when "missing_destination"
        values.merge!("direction" => "transfer", "category_id" => nil)
      end
      target = Transaction.create!(values)
      result, before, after = link(target)
      expect(result.reason).to eq("invalid_planned_target")
      expect(result.reason_codes).to include("payment_route_mismatch")
      expect(after).to eq(before)
    end
  end

  [["cafe", "café"], ["ハ", "バ"]].each do |rule_name, merchant|
    it "DB照合順序にかかわらず#{rule_name}と#{merchant}を別取引先にする" do
      source = draft.import_entry.import_document.import_source
      confirmed_rule(source: source, category: category, payment: payment, merchant: rule_name)
      document = import_document(source: source)
      candidate = ImageImportDraftBuilder.build([extraction_payload(merchant: merchant)], document: document).last.first
      expect(candidate.rule_decision["matched_rules"]).to eq([])
      expect(candidate.rule_decision["reason_codes"]).to include("rule_missing")
    end
  end
end
