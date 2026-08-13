class CategoriesController < ApplicationController
  before_action :set_category, only: [:edit, :update, :destroy]

  def index
    @expense_categories = Category.expense.order(:position, :name)
    @income_categories = Category.income.order(:position, :name)
  end

  def new
    kind = Category.kinds.key?(params[:kind]) ? params[:kind] : "expense"
    @category = Category.new(kind: kind)
  end

  def create
    @category = Category.new(category_params)
    if @category.save
      redirect_to categories_path, notice: "カテゴリ「#{@category.name}」を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @category.update(category_params)
      redirect_to categories_path, notice: "カテゴリ「#{@category.name}」を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @category.name
    if @category.destroy
      redirect_to categories_path, notice: "カテゴリ「#{name}」を削除しました。"
    else
      redirect_to categories_path, alert: @category.errors.full_messages.to_sentence
    end
  end

  private

  def set_category
    @category = Category.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:kind, :name, :monthly_budget, :note, :position)
  end
end
