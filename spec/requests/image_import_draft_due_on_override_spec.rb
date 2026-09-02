require "rails_helper"

RSpec.describe "image import draft payment due override carries through to the transaction", type: :request do
  before { Setting.current.update!(credit_card_closing_day: 31, credit_card_payment_day: 26) }

  let!(:category) { Category.create!(name: "食費", kind: :expense, position: 1) }
  let!(:payment_method) { PaymentMethod.create!(name: "クレカ", position: 1) }
  let!(:account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending, position: 1) }

  it "レビュー画面で支払予定日を手動で変更すると、登録された取引にも反映される" do
    draft = ImageImportDraft.create!(
      batch_id: "b1", date: Date.new(2028, 7, 25), direction: :expense, amount: 1000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )
    calculated = draft.calculated_credit_card_payment_due_on
    exceptional_due_on = calculated + 1.month

    patch bulk_approve_image_import_drafts_path(batch_id: "b1"), params: {
      draft_ids: [draft.id.to_s],
      drafts: {
        draft.id.to_s => {
          date: draft.date.to_s, direction: "expense", amount: "1000", memo: "",
          category_id: category.id.to_s, payment_method_id: payment_method.id.to_s, account_id: account.id.to_s,
          credit_card_status: "unpaid", credit_card_payment_due_on_override: exceptional_due_on.to_s
        }
      }
    }

    transaction = Transaction.order(:id).last
    expect(transaction.credit_card_payment_due_on).to eq(exceptional_due_on)
  end

  it "手動で変更しなかった(自動計算値のまま送信された)場合は上書きが残らない" do
    draft = ImageImportDraft.create!(
      batch_id: "b2", date: Date.new(2028, 7, 25), direction: :expense, amount: 1000,
      category: category, payment_method: payment_method, account: account, credit_card_status: :unpaid
    )
    calculated = draft.calculated_credit_card_payment_due_on

    patch bulk_approve_image_import_drafts_path(batch_id: "b2"), params: {
      draft_ids: [draft.id.to_s],
      drafts: {
        draft.id.to_s => {
          date: draft.date.to_s, direction: "expense", amount: "1000", memo: "",
          category_id: category.id.to_s, payment_method_id: payment_method.id.to_s, account_id: account.id.to_s,
          credit_card_status: "unpaid", credit_card_payment_due_on_override: calculated.to_s
        }
      }
    }

    transaction = Transaction.order(:id).last
    expect(transaction.credit_card_payment_due_on_override).to be_nil
    expect(transaction.credit_card_payment_due_on).to eq(calculated)
  end
end
