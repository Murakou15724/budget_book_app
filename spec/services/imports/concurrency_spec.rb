require "rails_helper"
require_relative "../../support/import_concurrency"

RSpec.describe "import concurrency", type: :model do
  self.use_transactional_tests = false
  include ImportConcurrency

  before { record_fixture_ids }
  after { cleanup_fixture_ids }

  def candidate
    account = Account.create!(name: "並行口座-#{SecureRandom.hex(4)}", kind: :bank)
    category = Category.create!(name: "並行費-#{SecureRandom.hex(4)}", kind: :expense)
    method = PaymentMethod.create!(name: "並行方法-#{SecureRandom.hex(4)}")
    tracked_draft(account: account, category: category, payment_method: method,
      date: Date.new(2026, 10, 1), direction: "expense", amount: 1000).import_entry
  end

  it "独立connectionで同じ候補を同時承認しても取引は1件" do
    entry = candidate
    ImportGuard.where(name: "ledger").delete_all
    expect(ImportGuard.count).to eq(0)
    count = Transaction.count
    results = concurrent(*2.times.map { -> { Imports::Applier.call(entry_id: entry.id, action: "approve") } })
    expect(results.map(&:status)).to contain_exactly(:applied, :already_processed)
    expect(Transaction.count).to eq(count + 1)
    expect(ImportGuard.where(name: "ledger").count).to eq(1)
  end

  it "承認と却下が競合しても先に確定した終端結果を維持する" do
    entry = candidate
    count = Transaction.count
    concurrent(-> { Imports::Applier.call(entry_id: entry.id, action: "approve") },
      -> { Imports::Applier.call(entry_id: entry.id, action: "reject") })
    expect(%w[applied rejected]).to include(entry.reload.state)
    expect(Transaction.count - count).to eq(entry.state == "applied" ? 1 : 0)
  end

  it "事前登録済みの類似2候補は並行承認しても両方を保留する" do
    first = candidate
    attrs = first.image_import_draft.transaction_attributes.except("entry_type")
    second = tracked_draft(**attrs.symbolize_keys, account: first.image_import_draft.account).import_entry
    count = Transaction.count
    results = concurrent(-> { Imports::Applier.call(entry_id: first.id, action: "approve") },
      -> { Imports::Applier.call(entry_id: second.id, action: "approve") })
    expect(results.map(&:status)).to eq([:held, :held])
    expect(Transaction.count).to eq(count)
  end

  it "schemaロード相当のGuard 0行から初回並行保存も直列化する" do
    ImportGuard.where(name: "ledger").delete_all
    inside = 0
    maximum = 0
    mutex = Mutex.new
    concurrent(*2.times.map do
      -> do
        ImportGuard.synchronize do
          mutex.synchronize { inside += 1; maximum = [maximum, inside].max }
          Thread.pass
          mutex.synchronize { inside -= 1 }
        end
      end
    end)
    expect(ImportGuard.where(name: "ledger").count).to eq(1)
    expect(maximum).to eq(1)
  end

  it "Guard 0行の初回rollback後にも次の通常取引保存が成功する" do
    entry = candidate
    ImportGuard.where(name: "ledger").delete_all
    ImportGuard.synchronize { raise ActiveRecord::Rollback }
    expect(ImportGuard.count).to eq(0)
    Transaction.create!(entry.image_import_draft.transaction_attributes)
    expect(ImportGuard.where(name: "ledger").count).to eq(1)
  end
end
