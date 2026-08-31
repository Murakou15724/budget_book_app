class ApplicationController < ActionController::Base
  # enumに定義されていない値が割り当てられた場合(不正なパラメータ改ざん等)に
  # 未処理の500ではなく400として応答する。
  rescue_from ArgumentError, with: :render_bad_request

  private

  def render_bad_request(exception)
    render "errors/show", status: :bad_request, locals: ErrorsController::ERROR_INFO.fetch(:bad_request).merge(
      message: exception.message, request_id: request.request_id
    )
  end

  # 年切り替えのある一覧画面(月別予算・月別集計・月次振り返り)共通の対象年解決ロジック。
  # 明示指定 > 全体設定の対象年 > 現在年 の順で採用する。
  def resolve_year(param_year)
    (param_year || Setting.current.target_year || Date.current.year).to_i
  end
end
