class ErrorsController < ApplicationController
  ERROR_INFO = {
    not_found: {
      icon: "🔍", title: "ページが見つかりません",
      message: "お探しのページは存在しないか、移動した可能性があります。"
    },
    unprocessable_entity: {
      icon: "⚠️", title: "リクエストを処理できませんでした",
      message: "入力内容に誤りがあるか、ページの有効期限が切れている可能性があります。もう一度お試しください。"
    },
    internal_server_error: {
      icon: "💥", title: "予期しないエラーが発生しました",
      message: "しばらく時間をおいて再度お試しください。解決しない場合は下記のリクエストIDを添えてご連絡ください。"
    },
    bad_request: {
      icon: "🚫", title: "不正なリクエストです",
      message: "リクエストの内容に誤りがあります。"
    }
  }.freeze

  def not_found
    render_error(:not_found, status: 404)
  end

  def unprocessable_entity
    render_error(:unprocessable_entity, status: 422)
  end

  def internal_server_error
    render_error(:internal_server_error, status: 500)
  end

  # 上記以外のステータス(405/406/501など)向けの汎用フォールバック。
  def show
    status = params[:status_code].to_i
    key = Rack::Utils::SYMBOL_TO_STATUS_CODE.find { |_, code| code == status }&.first
    render_error(ERROR_INFO.key?(key) ? key : :internal_server_error, status: status)
  end

  private

  def render_error(key, status:)
    render "errors/show", status: status, locals: ERROR_INFO.fetch(key).merge(request_id: request.request_id)
  end
end
