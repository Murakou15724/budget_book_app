class MonthlySummariesController < ApplicationController
  def index
    @year = resolve_year(params[:year])
    @monthly_summaries = MonthlySummary.build_for_year(@year)
  end
end
