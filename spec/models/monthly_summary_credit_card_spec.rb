require "rails_helper"

RSpec.describe MonthlySummary, ".build_for_month" do
  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:cash) { PaymentMethod.create!(name: "現金", position: 1) }
  let!(:credit) { PaymentMethod.create!(name: "クレカ", position: 2) }
  let!(:cash_account) { Account.create!(name: "現金", kind: :cash, position: 1) }
  let!(:credit_account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 2) }

  it "credit_card_expenseは利用日がその月のクレカ利用額のみを合計する(支払日は無関係)" do
    # 利用日は7月。設定次第で支払日は9月になるが、7月の集計に計上されるべき。
    Transaction.create!(
      date: Date.new(2028, 7, 20), entry_type: :actual, direction: :expense, amount: 4000,
      category: category, payment_method: credit, account: credit_account, credit_card_status: :unpaid
    )
    # 現金払いはクレカ利用額に含めない
    Transaction.create!(
      date: Date.new(2028, 7, 21), entry_type: :actual, direction: :expense, amount: 1000,
      category: category, payment_method: cash, account: cash_account, credit_card_status: :not_applicable
    )
    # 予定(planned)は実績集計に含めない
    Transaction.create!(
      date: Date.new(2028, 7, 22), entry_type: :planned, direction: :expense, amount: 9000,
      category: category, payment_method: credit, account: credit_account, credit_card_status: :unpaid
    )

    summary = MonthlySummary.build_for_month(2028, 7)

    expect(summary.credit_card_expense).to eq(4000)
    expect(summary.expense_actual).to eq(5000)
  end
end
