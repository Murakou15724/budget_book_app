require "rails_helper"

RSpec.describe "image import drafts payment due badge", type: :request do
  before do
    Setting.current.update!(credit_card_closing_day: 15, credit_card_payment_day: 26)
  end

  it "shows a payment due date badge for unpaid credit card drafts, but not for non-credit-card drafts" do
    unpaid_draft = ImageImportDraft.create!(
      batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 1000,
      credit_card_status: :unpaid
    )
    cash_draft = ImageImportDraft.create!(
      batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 500,
      credit_card_status: :not_applicable
    )

    get image_import_drafts_path(batch_id: "b1")

    expect(response.body).to include("支払予定: 10/26")
    expect(unpaid_draft.credit_card_payment_due_on).to eq(Date.new(2028, 10, 26))
    expect(cash_draft.credit_card_payment_due_on).to eq(Date.new(2028, 10, 26)) # メソッド自体は計算できる
  end
end
