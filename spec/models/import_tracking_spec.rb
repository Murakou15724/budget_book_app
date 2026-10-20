require "rails_helper"

RSpec.describe "import tracking constraints", type: :model do
  it "sourceのservice・口座は変更不可で、表示名だけ変更できる" do
    source = import_document.import_source
    expect(source.update(name: "別表示名")).to be(true)
    expect(source.update(service_key: "other")).to be(false)
    expect(source.reload.update(account_id: nil)).to be(false)
  end

  it "同じ入力・文書行はDB unique制約で保護する" do
    document = import_document
    expect { ImportDocument.transaction(requires_new: true) { ImportDocument.create!(document.attributes.except("id", "created_at", "updated_at")) } }.to raise_error(ActiveRecord::RecordNotUnique)
    draft = tracked_draft(document: document, amount: 100)
    entry = draft.import_entry
    expect { ImportEntry.transaction(requires_new: true) { ImportEntry.create!(entry.attributes.except("id", "created_at", "updated_at")) } }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "参照の循環・多段化を拒否する" do
    document = import_document
    first = tracked_draft(document: document, trusted_external_id: "id", amount: 100).import_entry
    second = tracked_draft(document: document, trusted_external_id: "id", amount: 100).import_entry
    third = tracked_draft(document: document, trusted_external_id: "id", amount: 100).import_entry
    expect(first.update(reference_entry: first)).to be(false)
    expect(third.update(reference_entry: second)).to be(false)
  end

  it "原payloadは許可項目のみで画像・秘密値を保存しない" do
    draft = tracked_draft(amount: 100, payload: { amount: 100, memo: "店", token: "secret-marker", bytes: "image-marker", authorization: "auth-marker" })
    expect(draft.import_entry.payload.keys).to contain_exactly("amount", "memo")
  end

  it "eventの通常更新・削除は拒否する" do
    event = tracked_draft(amount: 100).import_entry.import_events.first
    expect(event.update(kind: "edited")).to be(false)
    expect(event.destroy).to be(false)
  end
end
