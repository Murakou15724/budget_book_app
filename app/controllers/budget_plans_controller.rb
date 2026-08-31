class BudgetPlansController < ApplicationController
  def edit
    @year = resolve_year(params[:year])
    @categories = Category.expense.order(:position, :name)
    @existing_budgets = CategoryMonthlyBudget.where(year: @year).index_by { |b| [b.category_id, b.month] }
  end

  def update
    year = params[:year].to_i
    errors = []

    ActiveRecord::Base.transaction do
      # 月別の上書きが「基本月予算のまま(未上書き)」かどうかを判定する基準は、
      # このリクエストで基本月予算自体を変更した場合でも、変更前の値を使う。
      # (画面のプリフィルは変更前の値のままなので、変更後の値と比較すると
      #  意図せず全月が新しい上書きとして保存されてしまう)
      original_monthly_budgets = Category.expense.pluck(:id, :monthly_budget).to_h

      update_category_base_budgets(params[:categories], errors)

      (params[:budgets] || {}).each do |key, value|
        category_id, month = key.split("-")
        next if value.blank?

        category = Category.find_by(id: category_id)
        next unless category

        # 画面には未上書きの月にも基本月予算がプリフィルされているため、
        # 基本月予算と同値の送信は「上書きしない」とみなす(既存の上書きがあれば解除する)。
        if value.to_i == original_monthly_budgets[category.id]
          CategoryMonthlyBudget.find_by(category_id: category_id, year: year, month: month)&.destroy
          next
        end

        save_budget_override(category_id, year, month, value, errors)
      end
      raise ActiveRecord::Rollback if errors.any?
    end

    if errors.any?
      redirect_to edit_budget_plan_path(year: year), alert: errors.join(" / ")
    else
      redirect_to edit_budget_plan_path(year: year), notice: "#{year}年の月別予算を更新しました。"
    end
  end

  private

  def update_category_base_budgets(categories_params, errors)
    (categories_params || {}).each do |category_id, value|
      category = Category.find_by(id: category_id)
      next unless category

      unless category.update(monthly_budget: value.presence)
        errors << "カテゴリ「#{category.name}」の基本月予算: #{category.errors.full_messages.to_sentence}"
      end
    end
  end

  def save_budget_override(category_id, year, month, value, errors, attempt: 0)
    record = CategoryMonthlyBudget.find_or_initialize_by(category_id: category_id, year: year, month: month)
    record.budget = value
    unless record.save
      errors << "カテゴリID=#{category_id} #{month}月: #{record.errors.full_messages.to_sentence}"
    end
  rescue ActiveRecord::RecordNotUnique
    # find_or_initialize_by とDBのユニーク制約の間に競合(同時更新)が発生した場合、1回だけ再取得して retry する。
    raise if attempt >= 1

    save_budget_override(category_id, year, month, value, errors, attempt: attempt + 1)
  end
end
