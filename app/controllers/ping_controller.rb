# cronからの死活監視・スリープ防止用の応答専用コントローラ。ApplicationControllerは
# 継承せず、DBアクセスやビューレンダリングを一切行わないことで応答コストを最小化する。
class PingController < ActionController::Base
  def show
    head :ok
  end
end
