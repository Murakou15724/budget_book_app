require "rails_helper"

RSpec.describe MonthlySummary do
  describe "#ended?" do
    it "今日より前に最終日を迎えた月はtrue" do
      past_month = Date.current.prev_month
      summary = MonthlySummary.build_for_month(past_month.year, past_month.month)

      expect(summary.ended?).to be true
    end

    it "今月(進行中)はfalse" do
      today = Date.current
      summary = MonthlySummary.build_for_month(today.year, today.month)

      expect(summary.ended?).to be false
    end
  end

  describe "#income_estimate / #balance_estimate" do
    let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
    let!(:payment_method) { PaymentMethod.create!(name: "現金", position: 1) }
    let!(:account) { Account.create!(name: "現金口座", position: 1) }

    it "月別の上書きがあればそちらを、無ければ基本値(settings.monthly_income_estimate)を使う" do
      Setting.current.update!(monthly_income_estimate: 300_000)
      IncomeMonthlyEstimate.create!(year: 2028, month: 12, amount: 500_000)
      Transaction.create!(
        date: Date.new(2028, 7, 10), entry_type: :actual, direction: :expense, amount: 100_000,
        category: category, payment_method: payment_method, account: account
      )

      july = MonthlySummary.build_for_month(2028, 7)
      december = MonthlySummary.build_for_month(2028, 12)

      expect(july.income_estimate).to eq(300_000)
      expect(july.balance_estimate).to eq(200_000)
      expect(december.income_estimate).to eq(500_000)
    end

    it "基本値が未設定(nil)なら0として扱う" do
      summary = MonthlySummary.build_for_month(2028, 7)

      expect(summary.income_estimate).to eq(0)
    end
  end
end
