require "rails_helper"

RSpec.describe "asset reconciliation force align", type: :request do
  let!(:bank_account) { Account.create!(name: "銀行", kind: :bank, position: 1) }

  def snapshot_with(recorded_on:, balance:)
    snapshot = AssetSnapshot.create!(recorded_on: recorded_on)
    snapshot.asset_balances.create!(account: bank_account, balance: balance)
    snapshot
  end

  describe "GET /asset_snapshots/reconcile_preview" do
    it "差分があれば変更前後の内容を表示する" do
      snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 95_000)

      get reconcile_preview_asset_snapshots_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("この操作は元に戻せません")
      expect(response.body).to include("¥95,000")
      expect(response.body).to include("¥100,000")
    end

    it "差分がなければ実行できる操作がない旨を表示する" do
      snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 100_000)

      get reconcile_preview_asset_snapshots_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("実行できる操作はありません")
    end
  end

  describe "PATCH /asset_snapshots/force_align" do
    it "confirmedパラメータが無ければ実行せず確認画面へ差し戻す" do
      previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 95_000)

      patch force_align_asset_snapshots_path

      expect(response).to redirect_to(reconcile_preview_asset_snapshots_path)
      expect(previous.asset_balances.first.reload.balance).to eq(100_000)
    end

    it "確認画面通りのid・fingerprintが揃っていれば古い方のスナップショットだけを書き換える" do
      previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 95_000)
      plan = AccountReconciliation.force_align_plan(current, previous)

      patch force_align_asset_snapshots_path, params: {
        confirmed: "1", current_snapshot_id: current.id, previous_snapshot_id: previous.id,
        plan_fingerprint: AccountReconciliation.plan_fingerprint(plan)
      }

      expect(response).to redirect_to(asset_snapshots_path)
      expect(previous.asset_balances.first.reload.balance).to eq(95_000)
      expect(current.asset_balances.first.reload.balance).to eq(95_000)
    end

    it "確認画面表示後にスナップショット構成が変わっていれば実行せず確認画面へ差し戻す" do
      previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 95_000)
      plan = AccountReconciliation.force_align_plan(current, previous)
      fingerprint = AccountReconciliation.plan_fingerprint(plan)

      # 確認画面を表示した後、新しいスナップショットが追加された想定
      snapshot_with(recorded_on: Date.new(2028, 8, 15), balance: 95_000)

      patch force_align_asset_snapshots_path, params: {
        confirmed: "1", current_snapshot_id: current.id, previous_snapshot_id: previous.id,
        plan_fingerprint: fingerprint
      }

      expect(response).to redirect_to(reconcile_preview_asset_snapshots_path)
      expect(previous.asset_balances.first.reload.balance).to eq(100_000)
    end

    it "確認画面表示後に取引が追加されfingerprintが変わっていれば実行せず確認画面へ差し戻す" do
      category = Category.create!(name: "食費", kind: :expense, position: 1)
      payment_method = PaymentMethod.create!(name: "現金", position: 1)
      previous = snapshot_with(recorded_on: Date.new(2028, 7, 1), balance: 100_000)
      current = snapshot_with(recorded_on: Date.new(2028, 7, 31), balance: 95_000)
      plan = AccountReconciliation.force_align_plan(current, previous)
      fingerprint = AccountReconciliation.plan_fingerprint(plan)

      # 確認画面を表示した後、原因となる取引が追加された想定(見込み増減が変わる)
      Transaction.create!(
        date: Date.new(2028, 7, 10), entry_type: :actual, direction: :expense, amount: 5000,
        category: category, payment_method: payment_method, account: bank_account
      )

      patch force_align_asset_snapshots_path, params: {
        confirmed: "1", current_snapshot_id: current.id, previous_snapshot_id: previous.id,
        plan_fingerprint: fingerprint
      }

      expect(response).to redirect_to(reconcile_preview_asset_snapshots_path)
      expect(previous.asset_balances.first.reload.balance).to eq(100_000)
    end
  end
end
