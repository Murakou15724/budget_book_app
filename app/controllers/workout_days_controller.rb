class WorkoutDaysController < ApplicationController
  layout "workout"

  # 種目を動的に追加するJSは持たせず、固定枠数の空欄を用意することで
  # 1日に複数種目を記録できるようにする(個人利用の記録量であれば十分な数)。
  ENTRY_SLOTS = 5

  # 記録一覧の期間フィルタボタン。表示順もこの並びに従う。
  PERIOD_RANGES = [
    { key: "2w", label: "直近2週間", duration: 2.weeks },
    { key: "1m", label: "直近1ヶ月", duration: 1.month },
    { key: "all", label: "全期間", duration: nil }
  ].freeze
  helper_method :period_ranges

  before_action :set_workout_day, only: [:edit, :update, :destroy]

  def index
    @period_range = period_ranges.find { |range| range[:key] == params[:period] } || period_ranges.first
    start_date = @period_range[:duration] ? @period_range[:duration].ago.to_date : WorkoutSetting.current.start_date
    start_date = [start_date, WorkoutSetting.current.start_date].max
    dates = (start_date..Date.current).to_a.reverse

    # 記録が無い日も「未実施」として一覧に含めたいため、実在する行の有無に関わらず
    # 期間内の全日付を並べ、対応するWorkoutDayが無ければnilのまま渡す。
    workout_days_by_date = WorkoutDay.includes(workout_entries: :exercise).where(date: dates).index_by(&:date)
    @date_rows = dates.map { |date| [date, workout_days_by_date[date]] }
  end

  def new
    @workout_day = WorkoutDay.new(date: params[:date].presence || Date.current, status: :worked_out)
    build_blank_entries(@workout_day)
  end

  def create
    @workout_day = WorkoutDay.new(workout_day_params)

    if @workout_day.save
      redirect_to workout_days_path, notice: "記録を保存しました"
    else
      build_blank_entries(@workout_day)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    build_blank_entries(@workout_day)
  end

  def update
    if @workout_day.update(workout_day_params)
      redirect_to workout_days_path, notice: "記録を更新しました"
    else
      build_blank_entries(@workout_day)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @workout_day.destroy
    redirect_to workout_days_path, notice: "記録を削除しました"
  end

  private

  def period_ranges
    PERIOD_RANGES
  end

  def set_workout_day
    @workout_day = WorkoutDay.find(params[:id])
  end

  def build_blank_entries(workout_day)
    existing = workout_day.workout_entries.reject(&:marked_for_destruction?).size
    [ENTRY_SLOTS - existing, 0].max.times { workout_day.workout_entries.build }
  end

  def workout_day_params
    params.require(:workout_day).permit(
      :date, :status, :mood, :memo,
      workout_entries_attributes: [:id, :exercise_id, :sets, :reps, :weight_kg, :duration_min, :rpe, :_destroy]
    )
  end
end
