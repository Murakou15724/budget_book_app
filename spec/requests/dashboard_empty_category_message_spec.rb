require "rails_helper"

RSpec.describe "dashboard empty category expenses message", type: :request do
  it "当月の支出カテゴリが0件のとき、空状態メッセージが重複して表示されない" do
    get dashboard_path

    expect(response.body.scan("今月は表示できる支出カテゴリがありません。").size).to eq(1)
    expect(response.body).not_to include("カテゴリ別 今月支出(グラフ)")
  end
end
