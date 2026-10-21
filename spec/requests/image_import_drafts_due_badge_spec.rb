require "rails_helper"

RSpec.describe "image import drafts payment due date field", type: :request do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  it "未払候補だけに支払予定日の自動計算値を表示し非クレカへ送信しない" do
    unpaid_draft = tracked_draft(
      batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 1000,
      credit_card_status: :unpaid
    )
    cash_draft = tracked_draft(
      batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 500,
      credit_card_status: :not_applicable
    )

    get image_import_drafts_path(batch_id: "b1")

    expect(response.body).to include("name=\"drafts[#{unpaid_draft.id}][credit_card_payment_due_on_override]\"")
    expect(response.body).not_to include("name=\"drafts[#{cash_draft.id}][credit_card_payment_due_on_override]\"")
    expect(response.body.scan('value="2028-10-26"').size).to eq(1)
  end

  it "日付が未確定のドラフトにはフィールドを表示しない" do
    tracked_draft(batch_id: "b1", date: nil, direction: :expense, amount: 1000, credit_card_status: :unpaid)

    get image_import_drafts_path(batch_id: "b1")

    expect(response.body).not_to include("credit_card_payment_due_on_override")
  end
end
