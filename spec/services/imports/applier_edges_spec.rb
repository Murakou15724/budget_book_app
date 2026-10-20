require "rails_helper"

RSpec.describe "import decision boundaries", type: :model do
  let!(:account) { Account.create!(name: "境界口座", kind: :bank) }
  let!(:category) { Category.create!(name: "境界カテゴリ", kind: :expense) }
  let!(:payment_method) { PaymentMethod.create!(name: "境界方法") }
  let(:attrs) { { account: account, category: category, payment_method: payment_method, date: Date.new(2026, 12, 31), amount: 500, memo: "境界" } }
  let(:entry) { tracked_draft(**attrs).import_entry }

  def apply(candidate = entry, action: "approve", **options)
    Imports::Applier.call(entry_id: candidate.id, action: action, **options)
  end

  it "deadlockを外側から最大2回再試行して一度だけ反映する" do
    entry
    failures = 0
    allow(ImportGuard).to receive(:synchronize).and_wrap_original do |original, &block|
      if failures < 2
        failures += 1
        raise ActiveRecord::Deadlocked
      end
      original.call(&block)
    end
    expect { expect(apply.status).to eq(:applied) }.to change(Transaction, :count).by(1)
    expect(failures).to eq(2)
  end

  it "再試行上限に達した場合は未反映の候補を残す" do
    entry
    allow(ImportGuard).to receive(:synchronize).and_raise(ActiveRecord::LockWaitTimeout)
    expect(apply.status).to eq(:failed)
    expect(Transaction.count).to eq(0)
    expect(entry.reload.state).to eq("pending")
    expect(ImportGuard).to have_received(:synchronize).exactly(3).times
  end

  it "取引作成直後の失敗では外部IDのbindingを含めてrollbackし再実行できる" do
    candidate = tracked_draft(**attrs, trusted_external_id: "external-id").import_entry
    allow(Transaction).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
      transaction = original.call(*args, **kwargs)
      raise ActiveRecord::RecordInvalid.new(transaction)
    end
    expect { expect(apply(candidate).status).to eq(:failed) }.not_to change(Transaction, :count)
    expect(candidate.reload.target_transaction_id).to be_nil
    expect(candidate.import_identity.reload.bound_entry_id).to be_nil
    allow(Transaction).to receive(:create!).and_call_original
    expect { expect(apply(candidate).status).to eq(:applied) }.to change(Transaction, :count).by(1)
  end

  it "commit後の接続断は保存済み結果を再読込して返す" do
    entry
    depth = 0
    allow(ImportGuard).to receive(:synchronize).and_wrap_original do |original, &block|
      depth += 1
      outer = depth == 1
      begin
        value = original.call(&block)
        raise ActiveRecord::ConnectionFailed if outer
        value
      ensure
        depth -= 1
      end
    end
    expect { expect(apply.status).to eq(:already_processed) }.to change(Transaction, :count).by(1)
    expect(entry.reload.state).to eq("applied")
  end

  it "commit前の接続断なら未反映として失敗を返す" do
    entry
    allow(ImportGuard).to receive(:synchronize).and_raise(ActiveRecord::ConnectionFailed)
    expect(apply.status).to eq(:failed)
    expect(entry.reload.target_transaction_id).to be_nil
    expect(Transaction.count).to eq(0)
  end

  it "明示的な保留は普通の承認では解除せず、別取引の確認を必要とする" do
    expect(apply(action: "hold").status).to eq(:held)
    expect(apply.status).to eq(:held)
    expect(Transaction.count).to eq(0)
    expect(apply(action: "distinct", review_token: review_token(entry, "distinct")).status).to eq(:applied)
  end

  it "対象の差替えとプレビュー後の削除を拒否する" do
    first = Transaction.create!(entry.image_import_draft.transaction_attributes)
    second = Transaction.create!(entry.image_import_draft.transaction_attributes.merge(amount: 800))
    token = review_token(entry, "link", first)
    expect(apply(action: "link", target_id: second.id, review_token: token).status).to eq(:held)
    first.destroy!
    expect(apply(action: "link", target_id: first.id, review_token: token).status).to eq(:held)
    expect(entry.reload.target_transaction_id).to be_nil
  end

  it "年跨ぎの同額・同口座・同収支は確認対象で別口座は含めない" do
    target = Transaction.create!(entry.image_import_draft.transaction_attributes.merge(date: Date.new(2027, 1, 1)))
    another = Account.create!(name: "無関係口座", kind: :bank)
    unrelated = Transaction.create!(entry.image_import_draft.transaction_attributes.merge(account: another))
    match = ImportGuard.synchronize { Imports::Matcher.call(entry: entry, draft: entry.image_import_draft) }
    expect(match.transactions.map(&:id)).to contain_exactly(target.id)
    expect(match.transactions).not_to include(unrelated)
    expect(apply.status).to eq(:held)
  end

  it "同じ取引へ複数候補をlinkしても一つの矛盾確認で他の対応を解決しない" do
    first = entry
    target = Transaction.create!(first.image_import_draft.transaction_attributes)
    apply(first, action: "link", target_id: target.id, review_token: review_token(first, "link", target))
    second = tracked_draft(**attrs).import_entry
    apply(second, action: "link", target_id: target.id, review_token: review_token(second, "link", target))
    target.update!(memo: "変更後")
    expect([first.reload.state, second.reload.state]).to eq(%w[conflict conflict])
    apply(first, action: "acknowledge_current", review_token: review_token(first, "acknowledge_current"))
    expect(first.reload.state).to eq("linked")
    expect(second.reload.state).to eq("conflict")
  end

  it "マスタ名の変更だけでは矛盾にせず保存時の名前を履歴に残す" do
    apply
    account.update!(name: "変更後の口座名")
    Imports::TargetIntegrity.refresh!([entry])
    expect(entry.reload.state).to eq("applied")
    expect(entry.target_snapshot.dig("master_names", "account")).to eq("境界口座")
  end

  %w[user_held legacy_origin_unknown].each do |reason|
    it "#{reason}の停止理由を類似判定と比較先の消失後も維持する" do
      candidate = entry
      candidate.update!(state: "held", classification: "hold", reason_code: reason)
      target = Transaction.create!(candidate.image_import_draft.transaction_attributes)
      expect(apply(candidate).status).to eq(:held)
      expect(candidate.reload.reason_code).to eq(reason)
      target.destroy!
      expect(apply(candidate).status).to eq(:held)
      expect(candidate.reload.reason_code).to eq(reason)
      expect(Transaction.count).to eq(0)
    end
  end

  [true, false].each do |requires_approval|
    it "承認必須=#{requires_approval}でも通常反映APIは訂正・矛盾・保留を反映しない" do
      Setting.current.update!(image_import_requires_approval: requires_approval)
      document = import_document(account: account, state: "extracted")
      prior = tracked_draft(**attrs, document: document, trusted_external_id: "id", payload: { amount: 500 }).import_entry
      revision = tracked_draft(**attrs.merge(amount: 700), document: document, trusted_external_id: "id", payload: { amount: 700 }).import_entry
      expect(apply(revision).status).to eq(:held)
      expect(revision.reload.classification).to eq("correction")
      # 明示操作で選択した訂正版だけを反映する。
      expect(apply(revision, action: "adopt_revision", review_token: review_token(revision, "adopt_revision")).status).to eq(:applied)
      target = Transaction.find(revision.reload.target_transaction_id)
      target.update!(memo: "変更")
      expect(apply(revision).status).to eq(:conflict)
      held = tracked_draft(**attrs.merge(amount: 900)).import_entry
      apply(held, action: "hold")
      expect(apply(held).status).to eq(:held)
      expect(Transaction.count).to eq(1)
      expect(prior.reload.state).to eq("superseded")
    end
  end

  it "保存カラムの範囲を超える編集値はDB例外ではなく失敗として返す" do
    candidate = entry
    [ { amount: 2**40 }, { memo: "x" * 256 }, { category_id: 999999999 } ].each do |attributes|
      expect(apply(candidate, attributes: attributes).status).to eq(:failed)
      expect(candidate.reload.target_transaction_id).to be_nil
      expect(candidate.image_import_draft.reload.amount).to eq(500)
    end
    expect(Transaction.count).to eq(0)
  end
end
