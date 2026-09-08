require "rails_helper"

RSpec.describe "reaching old asset snapshots for edit/delete", type: :request do
  let!(:account) { Account.create!(name: "銀行", kind: :bank, position: 1) }

  let!(:old_snapshot) do
    snapshot = AssetSnapshot.create!(recorded_on: 2.years.ago.to_date)
    snapshot.asset_balances.create!(account: account, balance: 100_000)
    snapshot
  end

  let!(:latest_snapshot) do
    snapshot = AssetSnapshot.create!(recorded_on: Date.current)
    snapshot.asset_balances.create!(account: account, balance: 120_000)
    snapshot
  end

  it "デフォルト表示(直近1年)では、1年より古く最新でもないスナップショットの編集・削除リンクが無い" do
    get asset_snapshots_path

    expect(response.body).not_to include(edit_asset_snapshot_path(old_snapshot))
    expect(response.body).not_to include(asset_snapshot_path(old_snapshot))
  end

  it "全期間表示に切り替えると、古いスナップショットの編集・削除リンクが表示される" do
    get asset_snapshots_path(snapshots: "all")

    expect(response.body).to include(edit_asset_snapshot_path(old_snapshot))
    expect(response.body).to include("全期間")
  end
end
