class ExercisesController < ApplicationController
  layout "workout"

  before_action :set_exercise, only: [:edit, :update, :destroy]

  def index
    @exercises = Exercise.order(:name)
  end

  def new
    @exercise = Exercise.new
  end

  def create
    @exercise = Exercise.new(exercise_params)

    if @exercise.save
      redirect_to exercises_path, notice: "種目を追加しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @exercise.update(exercise_params)
      redirect_to exercises_path, notice: "種目を更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @exercise.destroy
      redirect_to exercises_path, notice: "種目を削除しました"
    else
      redirect_to exercises_path, alert: "この種目は記録で使用されているため削除できません"
    end
  end

  private

  def set_exercise
    @exercise = Exercise.find(params[:id])
  end

  def exercise_params
    params.require(:exercise).permit(:name, :body_part, :default_sets, :default_reps, :default_weight_kg, :default_duration_min, :memo)
  end
end
