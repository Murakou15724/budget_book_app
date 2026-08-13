class ApplicationController < ActionController::Base
  # enumに定義されていない値が割り当てられた場合(不正なパラメータ改ざん等)に
  # 未処理の500ではなく400として応答する。
  rescue_from ArgumentError, with: :render_bad_request

  private

  def render_bad_request(exception)
    render plain: exception.message, status: :bad_request
  end
end
