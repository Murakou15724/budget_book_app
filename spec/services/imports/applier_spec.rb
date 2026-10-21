require "rails_helper"

RSpec.describe Imports::Applier do
  include ActiveSupport::Testing::TimeHelpers
  let!(:category) { Category.create!(name: "食費", kind: :expense) }
  let!(:payment) { PaymentMethod.create!(import_kind: "cash", name: "現金") }
  let!(:account) { Account.create!(name: "財布", kind: :cash) }
  let(:attributes) { { account: account, category: category, payment_method: payment, date: Date.new(2026, 10, 1), direction: :expense, amount: 1000, memo: "店" } }
  let(:draft) { tracked_draft(**attributes) }
  let(:entry) { draft.import_entry }

  def apply(action = "approve", candidate = entry, **options)
    described_class.call(entry_id: candidate.id, action: action, **options)
  end

  it "承認後も候補と出所を保持し、再承認・再却下は確定結果を維持する" do
    expect { apply }.to change(Transaction, :count).by(1)
    expect(entry.reload.state).to eq("applied")
    expect(entry.target_snapshot["memo"]).to eq("店")
    expect { apply; apply("reject") }.not_to change(Transaction, :count)
    expect(entry.reload.state).to eq("applied")
    expect(draft.reload).to be_persisted
    expect(ImageImportDraft.pending).not_to include(draft)
  end

  it "類似手入力は通常承認を止め、明示linkでも既存取引を書き換えない" do
    target = Transaction.create!(draft.transaction_attributes.merge(memo: "手入力"))
    expect(apply.status).to eq(:held)
    token = review_token(entry, "link", target)
    expect { apply("link", entry, target_id: target.id, review_token: token) }.not_to change(Transaction, :count)
    expect(target.reload.memo).to eq("手入力")
    expect(entry.reload.target_transaction_id).to eq(target.id)
  end

  it "同日・同額・同店舗の2行を残し、明示的な別取引なら両方登録できる" do
    second = tracked_draft(**attributes, document: entry.import_document).import_entry
    expect(apply.status).to eq(:held)
    [entry, second].each do |candidate|
      token = review_token(candidate, "distinct")
      expect(apply("distinct", candidate, review_token: token).status).to eq(:applied)
    end
    expect(Transaction.count).to eq(2)
  end

  it "予定を同じIDで実績化し、金額・日付・メモは維持する" do
    target = Transaction.create!(draft.transaction_attributes.merge(entry_type: "planned", amount: 1300, memo: "予定"))
    token = review_token(entry, "link", target)
    expect { apply("link", entry, target_id: target.id, review_token: token) }.not_to change(Transaction, :count)
    expect(target.reload).to be_actual
    expect(target.amount).to eq(1300)
    expect(target.memo).to eq("予定")
  end

  it "取引保存直後のevent失敗は取引・状態・bindingすべてrollbackする" do
    entry
    count = ImportEvent.count
    allow_any_instance_of(ImportEvent).to receive(:save!).and_wrap_original do |original, *args, **kwargs|
      original.receiver.kind == "applied" ? raise(ActiveRecord::RecordInvalid.new(original.receiver)) : original.call(*args, **kwargs)
    end
    expect { apply }.not_to change(Transaction, :count)
    expect(entry.reload.target_transaction_id).to be_nil
    expect(entry.state).to eq("held")
    expect(ImportEvent.count).to eq(count + 1) # rollback後の失敗記録のみ
  end

  it "不正な取引値は修正可能な候補を保持する" do
    result = apply("distinct", entry, review_token: review_token(entry, "distinct"))
    expect(result.status).to eq(:applied)
    other = tracked_draft(**attributes.merge(amount: 0)).import_entry
    expect(apply("approve", other).status).to eq(:held)
    expect(other.reload.target_transaction_id).to be_nil
  end

  it "取引変更はconflictとなり、確認tokenによる明示操作で当該対応だけ維持する" do
    apply
    target = Transaction.find(entry.reload.target_transaction_id)
    target.update!(amount: 1200)
    expect(entry.reload.state).to eq("conflict")
    expect(apply.status).to eq(:conflict)
    token = review_token(entry, "acknowledge_current")
    apply("acknowledge_current", entry, review_token: token)
    expect(entry.reload.state).to eq("linked")
    expect(entry.target_snapshot["amount"]).to eq(1200)
  end

  it "削除確認後は履歴IDとsnapshotを保持し、閲覧・再承認で再生成しない" do
    apply
    target_id = entry.reload.target_transaction_id
    snapshot = entry.target_snapshot
    Transaction.find(target_id).destroy!
    expect(entry.reload.state).to eq("conflict")
    apply("acknowledge_deleted", entry, review_token: review_token(entry, "acknowledge_deleted"))
    expect(entry.reload.state).to eq("deletion_acknowledged")
    expect { apply; apply("reject"); Imports::TargetIntegrity.refresh!([entry]) }.not_to change(Transaction, :count)
    expect(entry.reload.state).to eq("deletion_acknowledged")
    expect(entry.target_transaction_id).to eq(target_id)
    expect(entry.target_snapshot).to eq(snapshot)
  end

  it "callbackを通らない変更も再承認時に検出する" do
    apply
    Transaction.where(id: entry.reload.target_transaction_id).update_all(amount: 777)
    expect(apply.status).to eq(:conflict)
    expect(Transaction.last.amount).to eq(777)
  end

  it "プレビュー後に比較候補が追加されるとtokenは使えない" do
    token = review_token(entry, "distinct")
    tracked_draft(**attributes)
    expect { expect(apply("distinct", entry, review_token: token).status).to eq(:held) }.not_to change(Transaction, :count)
  end

  it "token発行後に編集値を差し替えて承認できない" do
    token = review_token(entry, "distinct")
    expect(apply("distinct", entry, review_token: token, attributes: { amount: 700 }).status).to eq(:held)
    expect(draft.reload.amount).to eq(1000)
    expect(Transaction.count).to eq(0)
  end

  it "conflict確認のプレビュー後に対象が再変更されたら再確認を求める" do
    apply
    target = Transaction.find(entry.reload.target_transaction_id)
    target.update!(amount: 1200)
    token = review_token(entry, "acknowledge_current")
    target.update!(amount: 1300)
    expect(apply("acknowledge_current", entry, review_token: token).status).to eq(:held)
    expect(entry.reload.state).to eq("conflict")
    expect(entry.target_snapshot["amount"]).to eq(1000)
  end

  it "tokenの改ざん・操作差替え・対象差替え・期限切れを拒否する" do
    target = Transaction.create!(draft.transaction_attributes)
    token = review_token(entry, "link", target)
    expect(apply("link", entry, target_id: target.id, review_token: token + "x").status).to eq(:held)
    expect(apply("distinct", entry, review_token: token).status).to eq(:held)
    travel_to(31.minutes.from_now) do
      expect(apply("link", entry, target_id: target.id, review_token: token).status).to eq(:held)
    end
  end
end
