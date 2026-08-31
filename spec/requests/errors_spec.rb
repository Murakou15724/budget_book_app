require "rails_helper"

RSpec.describe "error pages via exceptions_app", type: :request do
  it "config.exceptions_app is wired to the router" do
    expect(Rails.application.config.exceptions_app).to eq(Rails.application.routes)
  end

  it "renders custom 404 when exceptions_app is invoked directly" do
    status, _headers, body = Rails.application.routes.call(Rack::MockRequest.env_for("/404"))
    expect(status).to eq(404)
    expect(body.each.to_a.join).to include("ページが見つかりません")
  end

  it "renders custom 422 when exceptions_app is invoked directly" do
    status, _headers, body = Rails.application.routes.call(Rack::MockRequest.env_for("/422"))
    expect(status).to eq(422)
    expect(body.each.to_a.join).to include("リクエストを処理できませんでした")
  end

  it "renders custom 500 when exceptions_app is invoked directly" do
    status, _headers, body = Rails.application.routes.call(Rack::MockRequest.env_for("/500"))
    expect(status).to eq(500)
    expect(body.each.to_a.join).to include("予期しないエラーが発生しました")
  end

  it "renders a generic fallback for other status codes (e.g. 405)" do
    status, _headers, body = Rails.application.routes.call(Rack::MockRequest.env_for("/405"))
    expect(status).to eq(405)
    expect(body.each.to_a.join).to include("予期しないエラーが発生しました")
  end

  it "still renders the shared error styling for invalid enum params via a real request" do
    category = Category.create!(name: "食費", kind: :expense, position: 1)
    payment_method = PaymentMethod.create!(name: "現金", position: 1)
    account = Account.create!(name: "現金口座", position: 1)

    post transactions_path, params: {
      transaction: {
        date: Date.today.to_s, entry_type: "actual", direction: "not_a_real_direction",
        amount: "1000", category_id: category.id, payment_method_id: payment_method.id, account_id: account.id
      }
    }

    expect(response.status).to eq(400)
    expect(response.body).to include("不正なリクエストです")
  end
end
