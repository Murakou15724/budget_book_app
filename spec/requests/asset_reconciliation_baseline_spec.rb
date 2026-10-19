require "rails_helper"

RSpec.describe "asset reconciliation baseline", type: :request do
  let!(:bank_account) { Account.create!(name: "銀行", kind: :bank, position: 1) }

  def snapshot_with(recorded_on:, balance:)
    snapshot = AssetSnapshot.create!(recorded_on: recorded_on)
    snapshot.asset_balances.create!(account: bank_account, balance: balance)
    snapshot
  end

  describe "GET /asset_snapshots/baseline_preview" do
    it "差分のある口座と差額を表示する" do
      snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 95_000)

      get baseline_preview_asset_snapshots_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("銀行")
      expect(response.body).to include("-¥5,000")
      expect(response.body).to include("過去のスナップショットの残高は変更しません")
    end

    it "差分がなければ実行できる操作がない旨を表示する" do
      snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 100_000)

      get baseline_preview_asset_snapshots_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("実行できる操作はありません")
    end
  end

  describe "PATCH /asset_snapshots/mark_baseline" do
    it "選択した口座の最新残高を起点にし、古い方のスナップショットは書き換えない" do
      previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 95_000)

      patch mark_baseline_asset_snapshots_path, params: { snapshot_id: current.id, account_ids: [bank_account.id] }

      expect(response).to redirect_to(asset_snapshots_path)
      expect(current.asset_balances.first.reload.reconciliation_baseline).to be(true)
      expect(previous.asset_balances.first.reload.balance).to eq(100_000)

      get asset_snapshots_path
      expect(response.body).not_to include("残高整合性チェック")
      expect(response.body).to include("集計の起点")
    end

    it "口座が選択されていなければ実行せず確認画面へ差し戻す" do
      snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 95_000)

      patch mark_baseline_asset_snapshots_path, params: { snapshot_id: current.id }

      expect(response).to redirect_to(baseline_preview_asset_snapshots_path)
      expect(current.asset_balances.first.reload.reconciliation_baseline).to be(false)
    end

    it "確認画面表示後に最新スナップショットが変わっていれば実行せず確認画面へ差し戻す" do
      snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 95_000)
      newer = snapshot_with(recorded_on: Date.new(2028, 8, 15), balance: 90_000)

      patch mark_baseline_asset_snapshots_path, params: { snapshot_id: current.id, account_ids: [bank_account.id] }

      expect(response).to redirect_to(baseline_preview_asset_snapshots_path)
      expect(current.asset_balances.first.reload.reconciliation_baseline).to be(false)
      expect(newer.asset_balances.first.reload.reconciliation_baseline).to be(false)
    end
  end

  describe "PATCH /asset_snapshots/:id/unmark_baseline" do
    it "起点を解除すると前回スナップショットとの差分が再び表示される" do
      snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 95_000)
      current.asset_balances.first.update!(reconciliation_baseline: true)

      patch unmark_baseline_asset_snapshot_path(current, account_id: bank_account.id)

      expect(response).to redirect_to(asset_snapshots_path)
      expect(current.asset_balances.first.reload.reconciliation_baseline).to be(false)

      get asset_snapshots_path
      expect(response.body).to include("残高整合性チェック")
    end
  end
end
