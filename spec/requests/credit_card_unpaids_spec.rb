require "rails_helper"

RSpec.describe "credit card unpaids grouped by payment due date", type: :request do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "クレカ", position: 1) }
  let!(:account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 1) }
  let!(:bank_account) { Account.create!(name: "銀行", kind: :bank, position: 2) }

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
      transaction_ids: [t1.id, t2.id], payment_account_id: bank_account.id
    }

    expect(t1.reload.credit_card_status).to eq("paid")
    expect(t2.reload.credit_card_status).to eq("paid")
    expect(other_cycle.reload.credit_card_status).to eq("unpaid")
    expect(other_cycle.account).to eq(account)
  end

  describe "引落元口座の選択" do
    it "支払済にした取引の口座を選択した引落元口座に変更し、支払予定日を引落日として記録する" do
      transaction = create_unpaid_transaction(Date.new(2028, 7, 20))

      patch mark_credit_card_paid_transactions_path, params: {
        transaction_ids: [transaction.id], payment_account_id: bank_account.id
      }

      transaction.reload
      expect(transaction.account).to eq(bank_account)
      expect(transaction.credit_card_paid_on).to eq(Date.new(2028, 9, 26))
      expect(flash[:notice]).to include("引落元: 銀行")
    end

    it "引落元口座が未選択の場合は支払済にしない" do
      transaction = create_unpaid_transaction(Date.new(2028, 7, 20))

      patch mark_credit_card_paid_transactions_path, params: { transaction_ids: [transaction.id] }

      expect(response).to redirect_to(credit_card_unpaids_path)
      expect(flash[:alert]).to eq("引落元口座を選択してください。")
      expect(transaction.reload.credit_card_status).to eq("unpaid")
      expect(transaction.account).to eq(account)
    end

    it "未払い以外の取引は、IDを送られても書き換えない" do
      paid = create_unpaid_transaction(Date.new(2028, 6, 20))
      paid.update!(credit_card_status: :paid)
      cash_method = PaymentMethod.create!(name: "現金", position: 2)
      not_applicable = Transaction.create!(
        date: Date.new(2028, 7, 20), entry_type: :actual, direction: :expense, amount: 500,
        category: category, payment_method: cash_method, account: account
      )

      expect do
        patch mark_credit_card_paid_transactions_path, params: {
          transaction_ids: [paid.id, not_applicable.id], payment_account_id: bank_account.id
        }
      end.not_to(change { [paid.reload.attributes, not_applicable.reload.attributes] })
      expect(flash[:notice]).to include("0件")
    end

    it "更新できない取引が含まれる場合は、原因を表示してすべて支払済にしない" do
      valid = create_unpaid_transaction(Date.new(2028, 7, 20))
      invalid = create_unpaid_transaction(Date.new(2028, 7, 21), amount: 2000)
      invalid.update_column(:category_id, nil)

      patch mark_credit_card_paid_transactions_path, params: {
        transaction_ids: [valid.id, invalid.id], payment_account_id: bank_account.id
      }

      expect(response).to redirect_to(credit_card_unpaids_path)
      expect(flash[:alert]).to include("2028-07-21 ¥2000")
      expect(valid.reload.credit_card_status).to eq("unpaid")
      expect(valid.account).to eq(account)
    end

    it "銀行以外の口座は引落元口座として受け付けない" do
      transaction = create_unpaid_transaction(Date.new(2028, 7, 20))
      paypay = Account.create!(name: "PayPay", kind: :e_money, position: 3)

      patch mark_credit_card_paid_transactions_path, params: {
        transaction_ids: [transaction.id], payment_account_id: paypay.id
      }

      expect(flash[:alert]).to eq("引落元口座を選択してください。")
      expect(transaction.reload.credit_card_status).to eq("unpaid")
    end

    it "選択肢は銀行口座のみで、設定の引落元口座を初期選択にする" do
      Account.create!(name: "PayPay", kind: :e_money, position: 3)
      other_bank = Account.create!(name: "ネット銀行", kind: :bank, position: 4)
      Setting.current.update!(credit_card_payment_account: other_bank)
      create_unpaid_transaction(Date.new(2028, 7, 20))

      get credit_card_unpaids_path

      options = Nokogiri::HTML(response.body).css("select[name='payment_account_id'] option")
      expect(options.map(&:text)).to eq(["選択してください", "銀行", "ネット銀行"])
      expect(options.find { |option| option["selected"] }&.text).to eq("ネット銀行")
    end

    it "設定の引落元口座が未設定の場合は未選択にする" do
      create_unpaid_transaction(Date.new(2028, 7, 20))

      get credit_card_unpaids_path

      options = Nokogiri::HTML(response.body).css("select[name='payment_account_id'] option")
      expect(options.select { |option| option["selected"] }).to be_empty
      expect(response.body).to match(/<select[^>]*name="payment_account_id"[^>]*required/)
    end

    it "設定の引落元口座が銀行以外の場合は未選択にする" do
      paypay = Account.create!(name: "PayPay", kind: :e_money, position: 3)
      Setting.current.update!(credit_card_payment_account: paypay)
      create_unpaid_transaction(Date.new(2028, 7, 20))

      get credit_card_unpaids_path

      options = Nokogiri::HTML(response.body).css("select[name='payment_account_id'] option")
      expect(options.map(&:text)).not_to include("PayPay")
      expect(options.select { |option| option["selected"] }).to be_empty
    end

    it "銀行口座が1件もない場合は登録を促す" do
      bank_account.destroy!
      create_unpaid_transaction(Date.new(2028, 7, 20))

      get credit_card_unpaids_path

      expect(response.body).to include("支払済にするには引落元となる銀行口座が必要です。")
    end
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
