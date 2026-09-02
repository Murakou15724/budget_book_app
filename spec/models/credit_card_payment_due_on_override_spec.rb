require "rails_helper"

RSpec.describe "credit_card_payment_due_on_override", type: :model do
  before { Setting.current.update!(credit_card_closing_day: 31, credit_card_payment_day: 26) }

  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "クレカ", position: 1) }
  let!(:account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 1) }

  def new_transaction(date)
    Transaction.new(
      date: date, entry_type: :actual, direction: :expense, amount: 1000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )
  end

  it "自動計算値と異なる値を保存すると、上書きとして保持される" do
    usage_date = Date.new(2028, 7, 25)
    calculated = new_transaction(usage_date).calculated_credit_card_payment_due_on
    exceptional_due_on = calculated + 1.month # 通常より1サイクル遅れた例外ケースを想定

    transaction = new_transaction(usage_date)
    transaction.credit_card_payment_due_on_override = exceptional_due_on
    transaction.save!

    expect(transaction.reload.credit_card_payment_due_on_override).to eq(exceptional_due_on)
    expect(transaction.credit_card_payment_due_on).to eq(exceptional_due_on)
  end

  it "自動計算値と同じ値を保存すると、上書きは保持されない(自動追従のまま)" do
    usage_date = Date.new(2028, 7, 25)
    calculated = new_transaction(usage_date).calculated_credit_card_payment_due_on

    transaction = new_transaction(usage_date)
    transaction.credit_card_payment_due_on_override = calculated
    transaction.save!

    expect(transaction.reload.credit_card_payment_due_on_override).to be_nil
    expect(transaction.credit_card_payment_due_on).to eq(calculated)
  end

  it "上書き後に締め日・支払日設定を変えても、上書きされた取引の支払予定日は変わらない" do
    usage_date = Date.new(2028, 7, 25)
    calculated = new_transaction(usage_date).calculated_credit_card_payment_due_on
    exceptional_due_on = calculated + 2.months

    transaction = new_transaction(usage_date)
    transaction.credit_card_payment_due_on_override = exceptional_due_on
    transaction.save!

    Setting.current.update!(credit_card_payment_day: 10)

    expect(transaction.reload.credit_card_payment_due_on).to eq(exceptional_due_on)
  end
end

RSpec.describe "ImageImportDraft credit_card_payment_due_on_override" do
  before { Setting.current.update!(credit_card_closing_day: 31, credit_card_payment_day: 26) }

  it "ImageImportDraftでも同じ上書きルールが適用される(Transactionと同じconcernを共用)" do
    draft = ImageImportDraft.new(date: Date.new(2028, 7, 25), direction: :expense, amount: 1000, batch_id: "b1")
    calculated = draft.calculated_credit_card_payment_due_on

    draft.credit_card_payment_due_on_override = calculated
    draft.save!
    expect(draft.reload.credit_card_payment_due_on_override).to be_nil

    draft.credit_card_payment_due_on_override = calculated + 1.month
    draft.save!
    expect(draft.reload.credit_card_payment_due_on).to eq(calculated + 1.month)
  end
end
