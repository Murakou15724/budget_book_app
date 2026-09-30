require "rails_helper"

RSpec.describe "asset snapshot new form prefill", type: :request do
  let!(:bank_account) { Account.create!(name: "銀行", kind: :bank, position: 1) }
  let!(:paypay_account) { Account.create!(name: "PayPay", kind: :e_money, position: 2) }

  def snapshot_with(recorded_on:, balances:)
    snapshot = AssetSnapshot.create!(recorded_on: recorded_on)
    balances.each { |account, balance| snapshot.asset_balances.create!(account: account, balance: balance) }
    snapshot
  end

  def balance_inputs
    Nokogiri::HTML(response.body).css("input[name$='[balance]']").to_h do |input|
      account_id = input.parent.at_css("input[name$='[account_id]']")["value"].to_i
      [account_id, input["value"]]
    end
  end

  it "最新のスナップショットの残高を初期値にし、記録のない口座は空欄にする" do
    # 登録順ではなく記録日で最新を判定することを確かめるため、新しい記録日の方を先に登録する
    snapshot_with(recorded_on: Date.new(2028, 8, 1), balances: { bank_account => 100_000 })
    snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 90_000, paypay_account => 3000 })

    get new_asset_snapshot_path

    expect(balance_inputs).to eq(bank_account.id => "100000", paypay_account.id => nil)
    expect(response.body).to include("前回(2028-08-01)の残高を初期表示しています。")
  end

  it "最新のスナップショットに残高の記録が無い場合は、それより古いスナップショットの値も使わず、注記も出さない" do
    snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 90_000 })
    AssetSnapshot.create!(recorded_on: Date.new(2028, 8, 1))

    get new_asset_snapshot_path

    expect(balance_inputs).to eq(bank_account.id => nil, paypay_account.id => nil)
    expect(response.body).not_to include("の残高を初期表示しています。")
  end

  it "スナップショットが無い場合は全て空欄で、注記も出さない" do
    get new_asset_snapshot_path

    expect(balance_inputs).to eq(bank_account.id => nil, paypay_account.id => nil)
    expect(response.body).not_to include("の残高を初期表示しています。")
  end

  it "編集画面は保存済みの値を表示し、最新のスナップショットの値で埋めない" do
    editing = snapshot_with(recorded_on: Date.new(2028, 7, 1), balances: { bank_account => 90_000 })
    snapshot_with(recorded_on: Date.new(2028, 8, 1), balances: { bank_account => 100_000, paypay_account => 3000 })

    get edit_asset_snapshot_path(editing)

    expect(balance_inputs).to eq(bank_account.id => "90000", paypay_account.id => nil)
  end

  it "登録でエラーになった場合は入力値を表示する" do
    snapshot_with(recorded_on: Date.new(2028, 8, 1), balances: { bank_account => 100_000, paypay_account => 3000 })

    post asset_snapshots_path, params: {
      asset_snapshot: {
        recorded_on: "",
        asset_balances_attributes: {
          "0" => { account_id: bank_account.id, balance: "105000" },
          "1" => { account_id: paypay_account.id, balance: "" }
        }
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(balance_inputs).to eq(bank_account.id => "105000", paypay_account.id => nil)
  end
end
