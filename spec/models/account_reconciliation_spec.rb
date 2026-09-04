require "rails_helper"

RSpec.describe AccountReconciliation do
  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:cash_method) { PaymentMethod.create!(name: "現金", position: 1) }
  let!(:transfer_method) { PaymentMethod.create!(name: "銀行振込", position: 2) }
  let!(:bank_account) { Account.create!(name: "銀行", kind: :bank, position: 1) }
  let!(:paypay_account) { Account.create!(name: "PayPay", kind: :e_money, position: 2) }

  def snapshot_with(recorded_on:, balances:)
    snapshot = AssetSnapshot.create!(recorded_on: recorded_on)
    balances.each { |account, balance| snapshot.asset_balances.create!(account: account, balance: balance) }
    snapshot
  end

  it "見込み通りの残高増減であれば差分を報告しない" do
    previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 100_000 })
    Transaction.create!(
      date: Date.new(2028, 7, 10), entry_type: :actual, direction: :expense, amount: 3000,
      category: category, payment_method: cash_method, account: bank_account
    )
    current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balances: { bank_account => 97_000 })

    expect(described_class.build_for(current, previous)).to be_empty
  end

  it "記録漏れ等で見込みと実際の残高増減が食い違う場合は差分を報告する" do
    previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 100_000 })
    # 取引を記録しないまま、実際の残高だけ5,000円減っている(記録漏れの想定)
    current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balances: { bank_account => 95_000 })

    mismatches = described_class.build_for(current, previous)

    expect(mismatches.size).to eq(1)
    expect(mismatches.first.account).to eq(bank_account)
    expect(mismatches.first.expected_delta).to eq(0)
    expect(mismatches.first.actual_delta).to eq(-5000)
    expect(mismatches.first.diff).to eq(-5000)
  end

  it "振替を記録していれば移動元・移動先双方の残高増減を説明できる" do
    previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 100_000, paypay_account => 0 })
    Transaction.create!(
      date: Date.new(2028, 7, 10), entry_type: :actual, direction: :transfer, amount: 10_000,
      payment_method: transfer_method, account: bank_account, to_account: paypay_account
    )
    current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balances: { bank_account => 90_000, paypay_account => 10_000 })

    expect(described_class.build_for(current, previous)).to be_empty
  end

  describe ".credit_card_pending_diff" do
    let!(:credit_pending_account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 3) }
    let!(:credit_method) { PaymentMethod.create!(name: "クレカ", position: 3) }

    it "スナップショット残高と未払いクレカ取引合計が一致すれば差分は0" do
      Transaction.create!(
        date: Date.new(2028, 7, 10), entry_type: :actual, direction: :expense, amount: 4000,
        category: category, payment_method: credit_method, account: credit_pending_account, credit_card_status: :unpaid
      )
      snapshot = snapshot_with(recorded_on: Date.new(2028, 7, 31), balances: { credit_pending_account => 4000 })

      expect(described_class.credit_card_pending_diff(snapshot)).to eq(0)
    end

    it "一致しない場合は差分を返す" do
      snapshot = snapshot_with(recorded_on: Date.new(2028, 7, 31), balances: { credit_pending_account => 4000 })

      expect(described_class.credit_card_pending_diff(snapshot)).to eq(4000)
    end
  end
end
