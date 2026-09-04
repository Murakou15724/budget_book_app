require "rails_helper"

# 振替・投資対応のUI変更(ダッシュボード/資産管理/設定/取引登録画面)が
# 例外なくレンダリングされることを確認するスモークテスト。
RSpec.describe "transfer/investment UI", type: :request do
  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:cash_method) { PaymentMethod.create!(name: "現金", position: 1) }
  let!(:bank_account) { Account.create!(name: "銀行", kind: :bank, position: 1) }
  let!(:paypay_account) { Account.create!(name: "PayPay", kind: :e_money, position: 2) }

  it "ダッシュボードに投資額の項目が表示される" do
    Transaction.create!(
      date: Date.current, entry_type: :actual, direction: :investment, amount: 50_000,
      payment_method: cash_method, account: bank_account, to_account: paypay_account
    )

    get dashboard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("今月の投資")
    expect(response.body).to include("年間投資")
  end

  it "資産管理画面が整合性チェックを含めて表示できる" do
    AssetSnapshot.create!(recorded_on: Date.current).asset_balances.create!(account: bank_account, balance: 100_000)

    get asset_snapshots_path

    expect(response).to have_http_status(:ok)
  end

  it "取引登録画面に振替・投資の選択肢と移動先口座欄が表示される" do
    get new_transaction_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("振替")
    expect(response.body).to include("移動先口座")
  end

  it "取引を振替として登録すると支出には計上されない" do
    post transactions_path, params: {
      transaction: {
        date: Date.current, entry_type: "actual", direction: "transfer", amount: 10_000,
        payment_method_id: cash_method.id, account_id: bank_account.id, to_account_id: paypay_account.id
      }
    }

    expect(response).to redirect_to(transactions_path)
    transaction = Transaction.last
    expect(transaction).to be_transfer
    expect(transaction.category_id).to be_nil
  end

  it "設定画面にクレカ引落元口座の項目が表示される" do
    get edit_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("クレジットカードの引落元口座")
  end
end
