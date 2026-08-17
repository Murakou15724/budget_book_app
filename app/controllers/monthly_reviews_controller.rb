class MonthlyReviewsController < ApplicationController
  before_action :validate_month, only: [:edit, :update]

  def index
    @year = resolve_year(params[:year])
    @monthly_summaries = MonthlySummary.build_for_year(@year)
    @reviews_by_month = MonthlyReview.where(year: @year).index_by(&:month)
  end

  def edit
    @summary = MonthlySummary.build_for_month(@year, @month)
    @monthly_review = MonthlyReview.find_or_initialize_by(year: @year, month: @month)
  end

  def update
    if save_review(attempt: 0)
      redirect_to monthly_reviews_path(year: @year), notice: "#{@year}年#{@month}月の振り返りを保存しました。"
    else
      @summary = MonthlySummary.build_for_month(@year, @month)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def validate_month
    @year = params[:year].to_i
    @month = params[:month].to_i
    return if (1..12).cover?(@month)

    redirect_to monthly_reviews_path(year: @year), alert: "月は1〜12の範囲で指定してください。"
  end

  # find_or_initialize_by とDBのユニーク制約(year, month)の間に競合(同時更新)が
  # 発生した場合、1回だけ再取得してretryする(budget_plans_controllerと同じ対策)。
  def save_review(attempt:)
    @monthly_review = MonthlyReview.find_or_initialize_by(year: @year, month: @month)
    @monthly_review.assign_attributes(monthly_review_params)
    @monthly_review.save
  rescue ActiveRecord::RecordNotUnique
    raise if attempt >= 1

    save_review(attempt: attempt + 1)
  end

  def monthly_review_params
    params.require(:monthly_review).permit(
      :satisfaction, :regret_note, :good_spending_note, :next_month_cut_note, :comment, :next_action
    )
  end
end
