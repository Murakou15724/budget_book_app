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

  describe "#candidate_causes" do
    let!(:cash_account) { Account.create!(name: "現金", kind: :cash, position: 3) }

    it "差額と同額の取引が別口座にあれば、口座の選び間違いの候補として提示する" do
      previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 100_000 })
      # 本来は銀行の支出だが、誤って現金口座で登録してしまった想定
      Transaction.create!(
        date: Date.new(2028, 7, 10), entry_type: :actual, direction: :expense, amount: 4860,
        category: category, payment_method: cash_method, account: cash_account
      )
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balances: { bank_account => 95_140 })

      mismatch = described_class.build_for(current, previous).first

      expect(mismatch.diff).to eq(-4860)
      expect(mismatch.candidate_causes.map(&:kind)).to include(:wrong_account)
      expect(mismatch.candidate_causes.first.message).to include("現金")
    end

    it "差額と同額の取引がこの口座内に複数あれば、二重登録の候補として提示する" do
      previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 100_000 })
      2.times do
        Transaction.create!(
          date: Date.new(2028, 7, 10), entry_type: :actual, direction: :expense, amount: 3000,
          category: category, payment_method: cash_method, account: bank_account
        )
      end
      # 実際には1回分(3,000円)しか引き落とされていない想定
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balances: { bank_account => 97_000 })

      mismatch = described_class.build_for(current, previous).first

      expect(mismatch.diff).to eq(3000)
      expect(mismatch.candidate_causes.map(&:kind)).to all(eq(:duplicate))
      expect(mismatch.candidate_causes.size).to eq(2)
    end

    it "振替の移動先としてすでに計上済みの取引は、口座選び間違いの候補に出さない" do
      previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 100_000, paypay_account => 50_000 })
      # PayPay -> 銀行への振替(10,000円)。これはすでにbank_accountの見込み増減に正しく計上される。
      Transaction.create!(
        date: Date.new(2028, 7, 10), entry_type: :actual, direction: :transfer, amount: 10_000,
        payment_method: transfer_method, account: paypay_account, to_account: bank_account
      )
      # さらに記録漏れ等で10,000円多く増えている(diff.abs がたまたま振替額と一致するケース)
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balances: { bank_account => 120_000, paypay_account => 40_000 })

      mismatches = described_class.build_for(current, previous)
      bank_mismatch = mismatches.find { |m| m.account == bank_account }

      expect(bank_mismatch.diff).to eq(10_000)
      expect(bank_mismatch.candidate_causes).to be_empty
    end

    it "見込み増減に寄与しない取引(クレカ未払い等)は、二重登録の候補に出さない" do
      previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 100_000 })
      # 支出だがcredit_card_status: unpaidのため、そもそもこの口座の見込み増減には寄与しない
      2.times do
        Transaction.create!(
          date: Date.new(2028, 7, 10), entry_type: :actual, direction: :expense, amount: 3000,
          category: category, payment_method: cash_method, account: bank_account, credit_card_status: :unpaid
        )
      end
      # 記録漏れ等で3,000円減っている(diff.abs が偶然その取引額と一致するケース)
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balances: { bank_account => 97_000 })

      mismatch = described_class.build_for(current, previous).first

      expect(mismatch.diff).to eq(-3000)
      expect(mismatch.candidate_causes).to be_empty
    end

    it "該当する取引がなければ空になる(記録漏れの可能性を示唆)" do
      previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 100_000 })
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balances: { bank_account => 95_000 })

      mismatch = described_class.build_for(current, previous).first

      expect(mismatch.candidate_causes).to be_empty
    end
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
