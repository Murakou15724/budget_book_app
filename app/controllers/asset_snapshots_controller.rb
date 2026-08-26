class AssetSnapshotsController < ApplicationController
  before_action :set_asset_snapshot, only: [:edit, :update, :destroy]

  # 資産推移グラフの期間フィルタボタン。表示順もこの並びに従う。
  CHART_RANGES = [
    { key: "3m", label: "直近3ヶ月", duration: 3.months },
    { key: "6m", label: "直近6ヶ月", duration: 6.months },
    { key: "1y", label: "直近1年", duration: 1.year },
    { key: "all", label: "全期間", duration: nil }
  ].freeze
  helper_method :chart_ranges

  def index
    @asset_snapshots = AssetSnapshot.includes(asset_balances: :account).order(recorded_on: :desc, id: :desc).to_a
    @latest_snapshot = @asset_snapshots.first
    @recent_snapshots = @asset_snapshots.select { |snapshot| snapshot.recorded_on >= 1.year.ago.to_date }
    @savings_goal = Setting.current.total_savings_goal
    @chart_range = chart_ranges.find { |range| range[:key] == params[:range] } || chart_ranges.first
    @chart_snapshots = chart_snapshots_for(@chart_range[:duration])
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

  def chart_ranges
    CHART_RANGES
  end

  # @asset_snapshots(記録日の降順)からグラフ表示対象を絞り込み、古い→新しい順で返す。
  def chart_snapshots_for(duration)
    snapshots = duration ? @asset_snapshots.select { |snapshot| snapshot.recorded_on >= duration.ago.to_date } : @asset_snapshots
    snapshots.reverse
  end

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
