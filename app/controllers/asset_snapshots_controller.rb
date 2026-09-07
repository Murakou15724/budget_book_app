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
    @asset_snapshots = AssetSnapshot.includes(asset_balances: :account).newest_first.to_a
    @latest_snapshot = @asset_snapshots.first
    @recent_snapshots = @asset_snapshots.select { |snapshot| snapshot.recorded_on >= 1.year.ago.to_date }
    @savings_goal = Setting.current.total_savings_goal
    @chart_range = chart_ranges.find { |range| range[:key] == params[:range] } || chart_ranges.first
    @chart_snapshots = chart_snapshots_for(@chart_range[:duration])

    @reconciliation_mismatches = AccountReconciliation.build_for(@latest_snapshot, @asset_snapshots[1])
    @credit_card_pending_diff = AccountReconciliation.credit_card_pending_diff(@latest_snapshot)
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

  # 残高整合性チェックの差分を強制的に解消する前の確認画面。
  # 実際の書き換えは行わず、変更前後の値を提示するだけ(警告1段階目)。
  # スナップショットのidと内容の指紋(fingerprint)をhidden fieldで持たせ、
  # force_align実行時に「確認画面を見てから内容が変わっていないか」を検証する。
  def reconcile_preview
    @current_snapshot, @previous_snapshot = latest_snapshot_pair
    @plan = @previous_snapshot ? AccountReconciliation.force_align_plan(@current_snapshot, @previous_snapshot) : []
    @fingerprint = AccountReconciliation.plan_fingerprint(@plan)
  end

  # 確認画面のチェックボックス同意(警告1段階目)とturbo_confirm(警告2段階目)の両方を
  # 経てここに届く想定。confirmedパラメータが無い直接アクセスは、対策として拒否する。
  # さらに、確認画面の表示後にスナップショット構成や取引内容が変わっていないかを
  # snapshot id・fingerprintの突合で検証し、食い違えば実行せず確認をやり直させる。
  def force_align
    if params[:confirmed] != "1"
      redirect_to reconcile_preview_asset_snapshots_path,
                  alert: "内容を確認し、チェックボックスにチェックの上で実行してください。"
      return
    end

    current_snapshot, previous_snapshot = latest_snapshot_pair
    if previous_snapshot.nil?
      redirect_to asset_snapshots_path, alert: "資産スナップショットが2件以上登録されている必要があります。"
      return
    end

    if current_snapshot.id.to_s != params[:current_snapshot_id] || previous_snapshot.id.to_s != params[:previous_snapshot_id]
      redirect_to reconcile_preview_asset_snapshots_path,
                  alert: "確認画面の表示後にスナップショットが変更されました。内容を再確認してください。"
      return
    end

    plan = AccountReconciliation.force_align_plan(current_snapshot, previous_snapshot)
    if AccountReconciliation.plan_fingerprint(plan) != params[:plan_fingerprint]
      redirect_to reconcile_preview_asset_snapshots_path,
                  alert: "確認画面の表示後に取引などの内容が変わりました。もう一度内容を確認してください。"
      return
    end

    if plan.empty?
      redirect_to asset_snapshots_path, notice: "差分はありませんでした。"
      return
    end

    AccountReconciliation.apply_plan!(plan)
    summary = plan.map { |step| "#{step.account.name}: #{step.old_value}円→#{step.new_value}円" }.join(" / ")
    redirect_to asset_snapshots_path,
                notice: "#{previous_snapshot.recorded_on}のスナップショットを書き換えました。#{summary}"
  end

  private

  def latest_snapshot_pair
    AssetSnapshot.includes(asset_balances: :account).newest_first.first(2)
  end

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
