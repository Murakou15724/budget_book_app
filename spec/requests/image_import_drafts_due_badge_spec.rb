require "rails_helper"

RSpec.describe "image import drafts payment due badge", type: :request do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  it "常に(現在のクレカ支払状況の選択に関わらず)支払予定日バッジを表示する" do
    ImageImportDraft.create!(
      batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 1000,
      credit_card_status: :unpaid
    )
    ImageImportDraft.create!(
      batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 500,
      credit_card_status: :not_applicable
    )

    get image_import_drafts_path(batch_id: "b1")

    expect(response.body.scan("未払で登録した場合の支払予定: 10/26").size).to eq(2)
  end

  it "日付が未確定のドラフトにはバッジを表示しない" do
    ImageImportDraft.create!(batch_id: "b1", date: nil, direction: :expense, amount: 1000, credit_card_status: :unpaid)

    get image_import_drafts_path(batch_id: "b1")

    expect(response.body).not_to include("支払予定")
  end
end
