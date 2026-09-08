class MonthlySummariesController < ApplicationController
  def index
    @year = resolve_year(params[:year])
    @monthly_summaries = MonthlySummary.build_for_year(@year)
  end

  # 進行中の月の実績収支を「未確定」として隠しておき、タップされたときだけ
  # Turboフレームでこの値を読み込む(リロードすればまた隠れた状態に戻る)。
  def actual_balance
    @year = params[:year].to_i
    @month = params[:month].to_i
    @summary = MonthlySummary.build_for_month(@year, @month)
    render layout: false
  end
end
