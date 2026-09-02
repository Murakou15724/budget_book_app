require "rails_helper"

RSpec.describe "image import drafts payment due date field", type: :request do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  it "常に(現在のクレカ支払状況の選択に関わらず)支払予定日を編集できるフィールドを表示する" do
    unpaid_draft = ImageImportDraft.create!(
      batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 1000,
      credit_card_status: :unpaid
    )
    cash_draft = ImageImportDraft.create!(
      batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 500,
      credit_card_status: :not_applicable
    )

    get image_import_drafts_path(batch_id: "b1")

    [unpaid_draft, cash_draft].each do |draft|
      expect(response.body).to include("name=\"drafts[#{draft.id}][credit_card_payment_due_on_override]\"")
    end
    expect(response.body.scan('value="2028-10-26"').size).to eq(2)
  end

  it "日付が未確定のドラフトにはフィールドを表示しない" do
    ImageImportDraft.create!(batch_id: "b1", date: nil, direction: :expense, amount: 1000, credit_card_status: :unpaid)

    get image_import_drafts_path(batch_id: "b1")

    expect(response.body).not_to include("credit_card_payment_due_on_override")
  end
end
