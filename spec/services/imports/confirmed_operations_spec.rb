require "rails_helper"

RSpec.describe "取込の確認付き操作" do
  let!(:account) { Account.create!(name: "確認元", kind: :bank) }
  let!(:category) { Category.create!(name: "確認費", kind: :expense) }
  let!(:payment) { PaymentMethod.create!(name: "確認銀行", import_kind: "bank") }
  let(:draft) { tracked_draft(account: account, category: category, payment_method: payment, date: Date.new(2026, 10, 1), amount: 1000, payload: extraction_payload) }
  let(:entry) { draft.import_entry }

  def apply
    expect(Imports::Applier.call(entry_id: entry.id, action: "approve").status).to eq(:applied)
    Transaction.find(entry.reload.target_transaction_id)
  end

  it "日付一括previewは無更新、updateは全件成功、再送は確定数を増やさない" do
    other = tracked_draft(account: account, amount: 1500, date: nil)
    before = [draft.attributes, other.attributes, ImportEvent.count]
    result = Imports::BulkDateUpdate.preview(entry_ids: [entry.id, other.import_entry_id, entry.id], date: "2026-10-05")
    expect([draft.reload.attributes, other.reload.attributes, ImportEvent.count]).to eq(before)
    expect(result.entries.size).to eq(2)
    expect(Imports::BulkDateUpdate.call(token: result.token).status).to eq(:updated)
    expect(draft.reload.date).to eq(Date.new(2026, 10, 5))
    expect(other.reload.date_origin).to eq("user")
    count = ImportEvent.count
    expect(Imports::BulkDateUpdate.call(token: result.token).status).to eq(:already_processed)
    expect(ImportEvent.count).to eq(count)
    expect(Transaction.count).to eq(0)
  end

  it "一括指定の古いtokenと処理済み混入は全件無更新" do
    other = tracked_draft(account: account, amount: 1500, date: nil)
    result = Imports::BulkDateUpdate.preview(entry_ids: [entry.id, other.import_entry_id], date: "2026-10-05")
    other.update!(memo: "変更")
    expect { Imports::BulkDateUpdate.call(token: result.token) }.to raise_error(ArgumentError)
    expect(draft.reload.date).to eq(Date.new(2026, 10, 1))
    apply
    expect { Imports::BulkDateUpdate.preview(entry_ids: [entry.id, other.import_entry_id], date: "2026-10-05") }.to raise_error(ArgumentError)
  end

  it "一括指定の0件・101件・不正日付・異purposeを拒否する" do
    [[], (1..101).to_a].each do |ids|
      expect { Imports::BulkDateUpdate.preview(entry_ids: ids, date: "2026-10-05") }.to raise_error(ArgumentError)
    end
    expect { Imports::BulkDateUpdate.preview(entry_ids: [entry.id], date: "2026-02-30") }.to raise_error(ArgumentError)
    token = Imports::RuleWriter.form
    expect { Imports::BulkDateUpdate.call(token: token) }.to raise_error(ArgumentError)
  end

  it "100件までを一括プレビューでき、途中失敗は全件rollbackする" do
    document = import_document(account: account, state: "extracted")
    drafts = 100.times.map { |i| tracked_draft(document: document, amount: i + 1, date: nil) }
    result = Imports::BulkDateUpdate.preview(entry_ids: drafts.map(&:import_entry_id), date: "2026-10-05")
    expect(result.entries.size).to eq(100)
    allow_any_instance_of(ImportEntry).to receive(:event!).and_wrap_original do |method, kind, **args|
      raise ArgumentError, "injected" if kind == "date_updated" && method.receiver.id == drafts[50].import_entry_id
      method.call(kind, **args)
    end
    expect { Imports::BulkDateUpdate.call(token: result.token) }.to raise_error(ArgumentError, "injected")
    expect(ImageImportDraft.where(id: drafts.map(&:id)).where.not(date: nil)).not_to exist
  end

  it "ルール作成は明示選択のみでnonce再送と内容差替えを区別する" do
    apply
    expect(ImportClassificationRule.count).to eq(0)
    token = Imports::RuleWriter.form(entry_id: entry.id)
    values = { import_source_id: entry.import_document.import_source_id, channel: "image", merchant_key: "店",
      direction: "expense", category_id: category.id, payment_method_id: payment.id, account_id: account.id,
      credit_card_status: "not_applicable", enabled: "1", priority: "100" }
    expect { Imports::RuleWriter.call(attributes: values, token: token, confirmed: "0") }.to raise_error(ArgumentError)
    rule = Imports::RuleWriter.call(attributes: values, token: token, confirmed: "1")
    expect(Imports::RuleWriter.call(attributes: values, token: token, confirmed: "1")).to eq(rule)
    expect { Imports::RuleWriter.call(attributes: values.merge(priority: "1"), token: token, confirmed: "1") }.to raise_error(ArgumentError)
    expect(ImportClassificationRule.count).to eq(1)
    expect(rule.confirmation_entry_id).to eq(entry.id)
  end

  it "元候補のない手動ルールもnonceで1件にし、架空文書を作らない" do
    source = import_document(account: account).import_source
    values = { import_source_id: source.id, channel: "image", merchant_key: "手動店", direction: "expense",
      category_id: category.id, payment_method_id: payment.id, account_id: account.id, credit_card_status: "not_applicable" }
    token = Imports::RuleWriter.form
    count = ImportDocument.count
    rule = Imports::RuleWriter.call(attributes: values, token: token, confirmed: "1")
    expect(rule).not_to be_enabled
    expect(Imports::RuleWriter.call(attributes: values, token: token, confirmed: "1").id).to eq(rule.id)
    expect(ImportDocument.count).to eq(count)
  end

  it "訂正previewと保存結果を一致させ、起点以外はconflictにする" do
    target = apply
    second = tracked_draft(account: account, category: category, payment_method: payment, date: draft.date, amount: draft.amount).import_entry
    Imports::Applier.call(entry_id: second.id, action: "link", target_id: target.id, review_token: review_token(second, "link", target))
    original = entry.import_events.find_by!(kind: "applied").details
    result = Imports::TransactionCorrection.preview(entry_id: entry.id, attributes: { amount: "1200", memo: "訂正" })
    expect(target.reload.amount).to eq(1000)
    Imports::TransactionCorrection.call(entry_id: entry.id, token: result.token)
    expect(Imports::Fingerprint.transaction_snapshot(target.reload)).to eq(result.after)
    expect(entry.reload.state).to eq("applied")
    expect(second.reload.state).to eq("conflict")
    expect(entry.import_events.find_by!(kind: "applied").details).to eq(original)
    count = ImportEvent.count
    expect(Imports::TransactionCorrection.call(entry_id: entry.id, token: result.token).status).to eq(:already_processed)
    expect(ImportEvent.count).to eq(count)
  end

  it "訂正preview後の設定変更では再プレビューを求める" do
    target = apply
    result = Imports::TransactionCorrection.preview(entry_id: entry.id, attributes: { memo: "変更" })
    Setting.current.update!(credit_card_payment_day: 15)
    expect { Imports::TransactionCorrection.call(entry_id: entry.id, token: result.token) }.to raise_error(ArgumentError)
    expect(target.reload.memo).not_to eq("変更")
  end

  it "訂正preview後の関連ルール停止では実績・候補・イベントを変更せず再確認を求める" do
    target = apply
    rule = confirmed_rule(source: entry.import_document.import_source, category: category, payment: payment)
    result = Imports::TransactionCorrection.preview(entry_id: entry.id, attributes: { memo: "変更" })
    rule.update!(enabled: false)
    before = [entry.reload.attributes, target.reload.attributes, ImportEvent.count]
    expect { Imports::TransactionCorrection.call(entry_id: entry.id, token: result.token) }.to raise_error(ArgumentError)
    expect([entry.reload.attributes, target.reload.attributes, ImportEvent.count]).to eq(before)
  end

  [ { date: "2026-11-05" }, { credit_card_payment_due_on_override: "2026-12-10" }, { memo: "メモだけ変更" } ].each do |values|
    it "引落日設定済みpaid実績の#{values.keys.join}変更でpreviewと全snapshotが一致する" do
      payment.update!(import_kind: "credit_card")
      target = Transaction.create!(date: "2026-10-01", direction: "expense", category: category, payment_method: payment,
        account: account, amount: 1000, entry_type: "actual", credit_card_status: "paid", credit_card_paid_on: "2026-11-26")
      entry.update!(state: "linked", target_transaction_id: target.id, target_snapshot: Imports::Fingerprint.transaction_snapshot(target))
      result = Imports::TransactionCorrection.preview(entry_id: entry.id, attributes: values)
      expect(target.reload.credit_card_paid_on).to eq(Date.new(2026, 11, 26))
      Imports::TransactionCorrection.call(entry_id: entry.id, token: result.token)
      expect(Imports::Fingerprint.transaction_snapshot(target.reload)).to eq(result.after)
      expect(target.credit_card_paid_on).to eq(Date.new(2026, 11, 26)) if values.key?(:memo)
    end
  end
end
