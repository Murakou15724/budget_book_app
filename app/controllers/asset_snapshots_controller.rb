class AssetSnapshotsController < ApplicationController
  before_action :set_asset_snapshot, only: [:edit, :update, :destroy]

  def index
    @asset_snapshots = AssetSnapshot.includes(asset_balances: :account).order(recorded_on: :desc, id: :desc).to_a
    @latest_snapshot = @asset_snapshots.first
    @recent_snapshots = @asset_snapshots.select { |snapshot| snapshot.recorded_on >= 1.year.ago.to_date }
    @savings_goal = Setting.current.total_savings_goal
  end

  def new
    @accounts = Account.order(:position, :name)
    @asset_snapshot = AssetSnapshot.new(recorded_on: Date.current)
    build_missing_balances(@asset_snapshot)
  end

  def create
    @accounts = Account.order(:position, :name)
    @asset_snapshot = AssetSnapshot.new(asset_snapshot_params)
    if @asset_snapshot.save
      redirect_to asset_snapshots_path, notice: "資産スナップショットを登録しました。"
    else
      build_missing_balances(@asset_snapshot)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @accounts = Account.order(:position, :name)
    build_missing_balances(@asset_snapshot)
  end

  def update
    @accounts = Account.order(:position, :name)
    if @asset_snapshot.update(asset_snapshot_params)
      redirect_to asset_snapshots_path, notice: "資産スナップショットを更新しました。"
    else
      build_missing_balances(@asset_snapshot)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @asset_snapshot.destroy
      redirect_to asset_snapshots_path, notice: "資産スナップショットを削除しました。"
    else
      redirect_to asset_snapshots_path, alert: @asset_snapshot.errors.full_messages.to_sentence
    end
  end

  private

  def set_asset_snapshot
    @asset_snapshot = AssetSnapshot.includes(asset_balances: :account).find(params[:id])
  end

  def asset_snapshot_params
    params.require(:asset_snapshot).permit(:recorded_on, :memo, asset_balances_attributes: [:id, :account_id, :balance])
  end

  # 新規/編集フォームで全口座分の入力欄を表示するため、未入力の口座には空のAssetBalanceをビルドする
  def build_missing_balances(asset_snapshot)
    existing_account_ids = asset_snapshot.asset_balances.map(&:account_id)
    @accounts.each do |account|
      next if existing_account_ids.include?(account.id)

      asset_snapshot.asset_balances.build(account: account)
    end
  end
end
