require 'rails_helper'

RSpec.describe Transaction, type: :model do
  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "現金", position: 1) }
  let!(:bank_account) { Account.create!(name: "銀行", kind: :bank, position: 1) }
  let!(:other_account) { Account.create!(name: "PayPay", kind: :e_money, position: 2) }

  def build_transaction(attrs = {})
    Transaction.new({
      date: Date.new(2028, 7, 1), entry_type: :actual, direction: :expense, amount: 1000,
      category: category, payment_method: payment_method, account: bank_account
    }.merge(attrs))
  end

  it "支出はカテゴリが必須" do
    transaction = build_transaction(direction: :expense, category: nil)

    expect(transaction).to be_invalid
    expect(transaction.errors[:category]).to be_present
  end

  it "振替・投資はカテゴリが任意" do
    transfer = build_transaction(direction: :transfer, category: nil)
    investment = build_transaction(direction: :investment, category: nil)

    expect(transfer).to be_valid
    expect(investment).to be_valid
  end

  it "支出以外ではクレカ支払状況を未払・支払済にできない" do
    transfer = build_transaction(direction: :transfer, category: nil, credit_card_status: :unpaid)

    expect(transfer).to be_invalid
    expect(transfer.errors[:credit_card_status]).to be_present
  end

  it "移動先口座は移動元口座と異なる必要がある" do
    transaction = build_transaction(direction: :transfer, category: nil, account: bank_account, to_account: bank_account)

    expect(transaction).to be_invalid
    expect(transaction.errors[:to_account]).to be_present
  end

  it "移動先口座が移動元と異なれば振替は有効" do
    transaction = build_transaction(direction: :transfer, category: nil, account: bank_account, to_account: other_account)

    expect(transaction).to be_valid
  end
end
