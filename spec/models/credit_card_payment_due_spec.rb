require "rails_helper"

RSpec.describe Transaction, "#credit_card_payment_due_on" do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  def build_transaction(date)
    category = Category.create!(name: "食費#{date}", kind: :expense, position: 1)
    payment_method = PaymentMethod.first_or_create!(name: "クレカ")
    account = Account.first_or_create!(name: "クレカ仮置き", kind: :credit_pending)
    Transaction.new(date: date, entry_type: :actual, direction: :expense, amount: 1000,
                     category: category, payment_method: payment_method, account: account)
  end

  it "7月後半の利用は9月26日払いになる" do
    expect(build_transaction(Date.new(2028, 7, 20)).credit_card_payment_due_on).to eq(Date.new(2028, 9, 26))
  end

  it "8月前半の利用も9月26日払いになる(7月後半分と同じ支払いにまとまる)" do
    expect(build_transaction(Date.new(2028, 8, 10)).credit_card_payment_due_on).to eq(Date.new(2028, 9, 26))
  end

  it "8月後半の利用は10月26日払いになる(次のサイクル)" do
    expect(build_transaction(Date.new(2028, 8, 20)).credit_card_payment_due_on).to eq(Date.new(2028, 10, 26))
  end

  it "支払日が土曜のときは翌平日(月曜)にずれる" do
    # 2026年12月26日は土曜日 -> 12月28日(月曜)にずれる
    expect(build_transaction(Date.new(2026, 10, 20)).credit_card_payment_due_on).to eq(Date.new(2026, 12, 28))
  end

  it "支払日の日にちが対象月の末日を超える場合は末日にクランプする" do
    Setting.current.update!(credit_card_payment_day: 31)
    # 締め月=2026年3月、払い月=2026年4月(30日までしかなく、4/30は平日なので週末調整は絡まない)
    expect(build_transaction(Date.new(2026, 3, 10)).credit_card_payment_due_on).to eq(Date.new(2026, 4, 30))
  end

  # Olive(三井住友カード フレキシブルペイ・クレジットモード)は月末締め・翌月26日払いで固定。
  # https://www.pricey.jp/web/articles/7066 の実例(8/1〜8/31利用→9/26払い 等)に基づく回帰テスト。
  context "月末締め・翌月26日払い(Oliveの実際の運用)" do
    before { Setting.current.update!(credit_card_closing_day: 31, credit_card_payment_day: 26) }

    it "8月中の利用(月初・月末どちらも)は9月26日払いになる" do
      expect(build_transaction(Date.new(2028, 8, 1)).credit_card_payment_due_on).to eq(Date.new(2028, 9, 26))
      expect(build_transaction(Date.new(2028, 8, 31)).credit_card_payment_due_on).to eq(Date.new(2028, 9, 26))
    end

    it "9月中の利用は10月26日払いになる" do
      expect(build_transaction(Date.new(2028, 9, 1)).credit_card_payment_due_on).to eq(Date.new(2028, 10, 26))
      expect(build_transaction(Date.new(2028, 9, 30)).credit_card_payment_due_on).to eq(Date.new(2028, 10, 26))
    end

    it "28日しかない2月の利用でも正しく翌月26日払いになる" do
      expect(build_transaction(Date.new(2027, 2, 28)).credit_card_payment_due_on).to eq(Date.new(2027, 3, 26))
    end
  end
end
