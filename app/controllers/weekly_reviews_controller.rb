class WeeklyReviewsController < ApplicationController
  layout "workout"

  # 週次レビュー一覧の期間フィルタボタン。表示順もこの並びに従う。
  PERIOD_RANGES = [
    { key: "1m", label: "直近1ヶ月", duration: 1.month },
    { key: "3m", label: "直近3ヶ月", duration: 3.months },
    { key: "6m", label: "直近6ヶ月", duration: 6.months },
    { key: "all", label: "全期間", duration: nil }
  ].freeze
  helper_method :period_ranges

  def index
    @period_range = period_ranges.find { |range| range[:key] == params[:period] } || period_ranges.first

    start_week = WorkoutSetting.current.start_date.beginning_of_week(:monday)
    current_week = Date.current.beginning_of_week(:monday)
    earliest_week = @period_range[:duration] ? [@period_range[:duration].ago.to_date.beginning_of_week(:monday), start_week].max : start_week

    week_starts = []
    week = current_week
    while week >= earliest_week
      week_starts << week
      week -= 7
    end

    reviews_by_date = WeeklyReview.where(week_start_date: week_starts).index_by(&:week_start_date)
    @weeks = week_starts.map { |date| reviews_by_date[date] || WeeklyReview.new(week_start_date: date) }
  end

  def edit
    @weekly_review = WeeklyReview.find_or_initialize_by(week_start_date: week_start_date_param)
  end

  def update
    @weekly_review = WeeklyReview.find_or_initialize_by(week_start_date: week_start_date_param)

    if @weekly_review.update(weekly_review_params)
      redirect_to weekly_reviews_path, notice: "週次レビューを保存しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def period_ranges
    PERIOD_RANGES
  end

  def week_start_date_param
    Date.parse(params[:week_start_date])
  end

  def weekly_review_params
    params.require(:weekly_review).permit(:win_pattern, :next_week_adjustment)
  end
end
