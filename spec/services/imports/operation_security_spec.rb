require "rails_helper"

RSpec.describe "取込の署名確認とルール作成元の再検証" do
  include ActiveSupport::Testing::TimeHelpers
  let!(:account) { Account.create!(name: "署名元", kind: :bank) }
  let!(:category) { Category.create!(name: "署名費", kind: :expense) }
  let!(:payment) { PaymentMethod.create!(name: "署名銀行", import_kind: "bank") }
  let(:draft) { tracked_draft(account: account, category: category, payment_method: payment, date: Date.new(2026, 10, 1), amount: 1000, payload: extraction_payload) }
  let(:entry) { draft.import_entry }

  def apply
    expect(Imports::Applier.call(entry_id: entry.id, action: "approve").status).to eq(:applied)
    Transaction.find(entry.reload.target_transaction_id)
  end

  def rule_attributes
    { import_source_id: entry.import_document.import_source_id, channel: "image", merchant_key: "店", direction: "expense",
      category_id: category.id, payment_method_id: payment.id, account_id: account.id, credit_card_status: "not_applicable" }
  end

  it "未反映候補からルールの確認tokenを発行せず履歴を追加しない" do
    entry
    before = [ImportClassificationRule.count, ImportEvent.count]
    expect { Imports::RuleWriter.form(entry_id: entry.id) }.to raise_error(ArgumentError)
    expect([ImportClassificationRule.count, ImportEvent.count]).to eq(before)
  end

  %w[changed deleted].each do |operation|
    it "フォーム発行後に元実績が#{operation}になったらルールもイベントも追加しない" do
      target = apply
      token = Imports::RuleWriter.form(entry_id: entry.id)
      values = rule_attributes
      operation == "changed" ? target.update!(memo: "変更済み") : target.destroy!
      before = [ImportClassificationRule.count, ImportEvent.count]
      expect { Imports::RuleWriter.call(attributes: values, token: token, confirmed: "1") }.to raise_error(ArgumentError)
      expect([ImportClassificationRule.count, ImportEvent.count]).to eq(before)
    end
  end

  %w[expired tampered].each do |operation|
    it "ルール作成tokenの#{operation}でルール・イベントを追加しない" do
      apply
      token = Imports::RuleWriter.form(entry_id: entry.id)
      values = rule_attributes
      before = [ImportClassificationRule.count, ImportEvent.count]
      token += "x" if operation == "tampered"
      travel_to(31.minutes.from_now) if operation == "expired"
      expect { Imports::RuleWriter.call(attributes: values, token: token, confirmed: "1") }.to raise_error(ArgumentError)
      expect([ImportClassificationRule.count, ImportEvent.count]).to eq(before)
    ensure
      travel_back
    end

    it "一括日付tokenの#{operation}で候補・イベントを変更しない" do
      result = Imports::BulkDateUpdate.preview(entry_ids: [entry.id], date: "2026-10-05")
      token = result.token
      before = [draft.reload.attributes, entry.reload.attributes, ImportEvent.count]
      token += "x" if operation == "tampered"
      travel_to(31.minutes.from_now) if operation == "expired"
      expect { Imports::BulkDateUpdate.call(token: token) }.to raise_error(ArgumentError)
      expect([draft.reload.attributes, entry.reload.attributes, ImportEvent.count]).to eq(before)
    ensure
      travel_back
    end

    it "実績訂正tokenの#{operation}で実績・候補・イベントを変更しない" do
      target = apply
      result = Imports::TransactionCorrection.preview(entry_id: entry.id, attributes: { memo: "変更" })
      token = result.token
      before = [entry.reload.attributes, target.reload.attributes, ImportEvent.count]
      token += "x" if operation == "tampered"
      travel_to(31.minutes.from_now) if operation == "expired"
      expect { Imports::TransactionCorrection.call(entry_id: entry.id, token: token) }.to raise_error(ArgumentError)
      expect([entry.reload.attributes, target.reload.attributes, ImportEvent.count]).to eq(before)
    ensure
      travel_back
    end
  end
end
