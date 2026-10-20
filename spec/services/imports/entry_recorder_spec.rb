require "rails_helper"

RSpec.describe Imports::EntryRecorder do
  let!(:category) { Category.create!(name: "食費", kind: :expense) }
  let!(:payment) { PaymentMethod.create!(name: "電子マネー") }
  let!(:account) { Account.create!(name: "残高", kind: :e_money) }
  let(:attributes) { { account: account, category: category, payment_method: payment, date: Date.new(2026, 9, 30), direction: :expense, amount: 500, memo: "店" } }
  let(:document) { import_document(account: account) }

  def record(id, document: self.document, amount: 500, **payload)
    tracked_draft(**attributes.merge(amount: amount), document: document, trusted_external_id: id,
      payload: { "amount" => amount, "date" => "2026-09-30", "direction" => "expense", "memo" => "店" }.merge(payload.stringify_keys)).import_entry
  end

  it "同じ外部ID・同じ内容は代表を直接参照し、登録・確認を繰り返さない" do
    first = record("000Ab")
    expect(Imports::Applier.call(entry_id: first.id, action: "approve").status).to eq(:applied)
    second = record("000Ab", document: import_document(source: document.import_source))
    expect(second.reference_entry_id).to eq(first.id)
    expect { Imports::Applier.call(entry_id: second.id, action: "approve") }.not_to change(Transaction, :count)
    expect(second.summary_classification).to eq("duplicate")
  end

  it "前ゼロ・大小文字・長いIDを変更せず、別service・口座の同じIDは別identityにする" do
    ids = ["000Ab", "Ab", "000ab", "Z" * 1500]
    entries = ids.map { |id| record(id) }
    expect(entries.map(&:import_identity_id).uniq.size).to eq(4)
    expect(entries.last.import_identity.external_id).to eq(ids.last)
    other = record("000Ab", document: import_document(account: account))
    expect(other.import_identity_id).not_to eq(entries.first.import_identity_id)
    other_account = Account.create!(name: "別口座", kind: :bank)
    other_source = ImportSource.create!(service_key: document.import_source.service_key, name: "別口座", account: other_account)
    third = record("000Ab", document: import_document(source: other_source))
    expect(third.import_identity_id).not_to eq(entries.first.import_identity_id)
  end

  it "反映済みIDの訂正は保留し、別取引・新規承認から再登録できない" do
    first = record("id")
    Imports::Applier.call(entry_id: first.id, action: "approve")
    revision = record("id", amount: 700)
    ImportGuard.synchronize { Imports::Matcher.classify!(revision) }
    expect(revision.reload.classification).to eq("correction")
    expect { %w[approve distinct adopt_revision].each { |action| Imports::Applier.call(entry_id: revision.id, action: action, review_token: review_token(revision, action)) } }.not_to change(Transaction, :count)
    expect(Transaction.last.amount).to eq(500)
  end

  it "まだ反映していないIDの訂正版を採用すると先行版を終了し取引は1件になる" do
    first = record("id")
    revision = record("id", amount: 700)
    token = review_token(revision, "adopt_revision")
    result = Imports::Applier.call(entry_id: revision.id, action: "adopt_revision", review_token: token)
    expect(result.status).to eq(:applied)
    expect(first.reload.state).to eq("superseded")
    expect(Transaction.count).to eq(1)
    expect(revision.import_identity.reload.bound_entry_id).to eq(revision.id)
  end

  it "削除確認済みの代表と参照・後続版は再生成や確認を繰り返さない" do
    first = record("id")
    Imports::Applier.call(entry_id: first.id, action: "approve")
    Transaction.find(first.reload.target_transaction_id).destroy!
    Imports::Applier.call(entry_id: first.id, action: "acknowledge_deleted", review_token: review_token(first, "acknowledge_deleted"))
    reference = record("id")
    revision = record("id", amount: 600)
    expect { [first, reference, revision].each { |e| Imports::Applier.call(entry_id: e.id, action: "approve") } }.not_to change(Transaction, :count)
    expect(first.reload.state).to eq("deletion_acknowledged")
    expect(reference.effective_entry.state).to eq("deletion_acknowledged")
  end

  it "版digestは推定分類を無視し、原状態や日付・欠落と空文字は区別する" do
    first = record("id", category_name: "推定A")
    same = record("id", category_name: "推定B")
    changed = record("id", source_status: "cancelled")
    expect(same.reference_entry_id).to eq(first.id)
    expect(changed.reference_entry_id).to be_nil
    expect(Imports::Fingerprint.digest({})).not_to eq(Imports::Fingerprint.digest({ "memo" => "" }))
  end

  it "外部IDのdigest衝突は同一扱いしない" do
    first = record("id")
    allow(Digest::SHA256).to receive(:hexdigest).and_call_original
    allow(Digest::SHA256).to receive(:hexdigest).with("different".b).and_return(first.import_identity.external_id_digest)
    expect { record("different") }.to raise_error(Imports::EntryRecorder::IdentityCollision)
  end
end
