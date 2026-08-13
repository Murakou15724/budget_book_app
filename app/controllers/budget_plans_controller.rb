class BudgetPlansController < ApplicationController
  def edit
    @year = (params[:year] || Setting.current.target_year || Date.current.year).to_i
    @categories = Category.expense.order(:position, :name)
    @existing_budgets = CategoryMonthlyBudget.where(year: @year).index_by { |b| [b.category_id, b.month] }
  end

  def update
    year = params[:year].to_i
    errors = []

    ActiveRecord::Base.transaction do
      (params[:budgets] || {}).each do |key, value|
        category_id, month = key.split("-")
        next if value.blank?

        record = CategoryMonthlyBudget.find_or_initialize_by(category_id: category_id, year: year, month: month)
        record.budget = value
        unless record.save
          errors << "カテゴリID=#{category_id} #{month}月: #{record.errors.full_messages.to_sentence}"
        end
      end
      raise ActiveRecord::Rollback if errors.any?
    end

    if errors.any?
      redirect_to edit_budget_plan_path(year: year), alert: errors.join(" / ")
    else
      redirect_to edit_budget_plan_path(year: year), notice: "#{year}年の月別予算を更新しました。"
    end
  end
end
