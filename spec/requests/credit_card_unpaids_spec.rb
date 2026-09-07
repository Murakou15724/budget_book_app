require "rails_helper"

RSpec.describe "credit card unpaids grouped by payment due date", type: :request do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "クレカ", position: 1) }
  let!(:account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 1) }

  def create_unpaid_transaction(date, amount: 1000)
    Transaction.create!(
      date: date, entry_type: :actual, direction: :expense, amount: amount,
      category: category, payment_method: payment_method, account: account,
      credit_card_status: :unpaid
    )
  end

  it "groups unpaid transactions by their computed payment due date" do
    t1 = create_unpaid_transaction(Date.new(2028, 7, 20))
    t2 = create_unpaid_transaction(Date.new(2028, 8, 10))
    t3 = create_unpaid_transaction(Date.new(2028, 8, 20))

    get credit_card_unpaids_path

    expect(response.body).to include("9月26日払い分")
    expect(response.body).to include("10月26日払い分")
    [t1, t2, t3].each { |t| expect(response.body).to include(t.id.to_s) }
  end

  it "marks only the selected transactions as paid" do
    t1 = create_unpaid_transaction(Date.new(2028, 7, 20))
    t2 = create_unpaid_transaction(Date.new(2028, 8, 10))
    other_cycle = create_unpaid_transaction(Date.new(2028, 8, 20))

    patch mark_credit_card_paid_transactions_path, params: {
      transaction_ids: [t1.id, t2.id], return_to: "credit_card_unpaids"
    }

    expect(t1.reload.credit_card_status).to eq("paid")
    expect(t2.reload.credit_card_status).to eq("paid")
    expect(other_cycle.reload.credit_card_status).to eq("unpaid")
  end

  it "誤操作で意図しない取引まで支払済にしないよう、チェックボックスは初期状態で未選択にする" do
    create_unpaid_transaction(Date.new(2028, 7, 20))

    get credit_card_unpaids_path

    expect(response.body).not_to match(/name="select_all_[^"]*" value="1" checked/)
    expect(response.body).not_to match(/name="transaction_ids\[\]"[^>]*checked/)
  end

  it "前月/次月ボタンには誤クリック対策の確認ダイアログが付く" do
    create_unpaid_transaction(Date.new(2028, 7, 20))

    get credit_card_unpaids_path

    expect(response.body).to include('data-turbo-confirm="この取引の支払予定日を前月に変更しますか？"')
    expect(response.body).to include('data-turbo-confirm="この取引の支払予定日を次月に変更しますか？"')
  end
end
