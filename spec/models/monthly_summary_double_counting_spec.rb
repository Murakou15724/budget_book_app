require "rails_helper"

# 支出の二重計上防止(クレカ引落・電子マネーチャージ・口座振替・証券口座入金)を
# MonthlySummary.build_for_month の支出合計/投資額で検証する。
RSpec.describe MonthlySummary, ".build_for_month (二重計上防止)" do
  let!(:food_category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:cash_method) { PaymentMethod.create!(name: "現金", position: 1) }
  let!(:credit_method) { PaymentMethod.create!(name: "クレカ", position: 2) }
  let!(:e_money_method) { PaymentMethod.create!(name: "PayPay", position: 3) }
  let!(:bank_transfer_method) { PaymentMethod.create!(name: "銀行振込", position: 4) }
  let!(:securities_method) { PaymentMethod.create!(name: "証券入金", position: 5) }

  let!(:cash_account) { Account.create!(name: "現金", kind: :cash, position: 1) }
  let!(:credit_pending_account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 2) }
  let!(:smbc_account) { Account.create!(name: "三井住友銀行", kind: :bank, position: 3) }
  let!(:paypay_account) { Account.create!(name: "PayPay", kind: :e_money, position: 4) }
  let!(:paypay_bank_account) { Account.create!(name: "PayPay銀行", kind: :bank, position: 5) }
  let!(:sbi_account) { Account.create!(name: "SBI証券", kind: :securities, position: 6) }

  # ケース1: 現金で3,000円購入 -> 支出合計3,000円
  it "現金購入は支出として1回だけ計上される" do
    Transaction.create!(
      date: Date.new(2028, 7, 10), entry_type: :actual, direction: :expense, amount: 3000,
      category: food_category, payment_method: cash_method, account: cash_account
    )

    summary = MonthlySummary.build_for_month(2028, 7)

    expect(summary.expense_actual).to eq(3000)
  end

  # ケース2: カードで3,000円購入(利用時=未払) -> 翌月支払済に更新するだけで、
  # 新規の支出取引は作らない -> 支出合計は3,000円のまま(6,000円にならない)
  it "クレカ利用は未払→支払済への更新だけで、引落時に二重計上されない" do
    purchase = Transaction.create!(
      date: Date.new(2028, 7, 10), entry_type: :actual, direction: :expense, amount: 3000,
      category: food_category, payment_method: credit_method, account: credit_pending_account,
      credit_card_status: :unpaid
    )

    # 引落日(翌月)には、要件通り新しい取引を作らずステータス更新のみ行う。
    purchase.update!(credit_card_status: :paid)

    summary_july = MonthlySummary.build_for_month(2028, 7)
    summary_august = MonthlySummary.build_for_month(2028, 8)

    expect(summary_july.expense_actual).to eq(3000)
    expect(summary_august.expense_actual).to eq(0)
  end

  # ケース3: 銀行->PayPay 10,000円チャージ(振替) + PayPayで3,000円購入(支出)
  # -> 支出合計は3,000円(13,000円にならない)
  it "電子マネーへのチャージは振替、実際の利用時のみ支出になる" do
    Transaction.create!(
      date: Date.new(2028, 7, 5), entry_type: :actual, direction: :transfer, amount: 10_000,
      payment_method: bank_transfer_method, account: smbc_account, to_account: paypay_account
    )
    Transaction.create!(
      date: Date.new(2028, 7, 10), entry_type: :actual, direction: :expense, amount: 3000,
      category: food_category, payment_method: e_money_method, account: paypay_account
    )

    summary = MonthlySummary.build_for_month(2028, 7)

    expect(summary.expense_actual).to eq(3000)
  end

  # ケース4: 三井住友銀行->PayPay銀行 50,000円の口座間振替 -> 支出合計は0円
  it "口座間振替は支出に計上されない" do
    Transaction.create!(
      date: Date.new(2028, 7, 5), entry_type: :actual, direction: :transfer, amount: 50_000,
      payment_method: bank_transfer_method, account: smbc_account, to_account: paypay_bank_account
    )

    summary = MonthlySummary.build_for_month(2028, 7)

    expect(summary.expense_actual).to eq(0)
  end

  # ケース5: 銀行->SBI証券 50,000円 -> 生活費の支出合計は0円、投資額としては50,000円確認できる
  it "証券口座への入金は投資として別枠になり、支出合計には含まれない" do
    Transaction.create!(
      date: Date.new(2028, 7, 5), entry_type: :actual, direction: :investment, amount: 50_000,
      payment_method: securities_method, account: smbc_account, to_account: sbi_account
    )

    summary = MonthlySummary.build_for_month(2028, 7)

    expect(summary.expense_actual).to eq(0)
    expect(summary.investment_actual).to eq(50_000)
  end
end
