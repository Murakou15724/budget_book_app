require 'rails_helper'

RSpec.describe ImageImportDraftBuilder do
  let!(:expense_category) { Category.create!(kind: :expense, name: "食費") }
  let!(:payment_method) { PaymentMethod.create!(import_kind: "credit_card", name: "クレカ") }
  let!(:credit_pending_account) { Account.create!(name: "クレカ仮置き", kind: :credit_pending) }

  let(:document) { import_document(account: credit_pending_account) }

  it "マスタと完全一致すればidを解決し、クレカ仮置き口座なら未払いを自動設定する" do
    items = [
      { "date" => "2026-08-01", "direction" => "expense", "amount" => 1000, "memo" => "テスト",
        "category_name" => "食費", "payment_method_name" => "クレカ", "account_name" => "クレカ仮置き" }
    ]

    batch_id, drafts = ImageImportDraftBuilder.build(items, document: document)
    draft = drafts.first

    expect(batch_id).to be_present
    expect(draft.category).to eq(expense_category)
    expect(draft.payment_method).to eq(payment_method)
    expect(draft.account).to eq(credit_pending_account)
    expect(draft).to be_unpaid
  end

  it "一致しない名前はsuggested_*に保持しidはnilのままになる" do
    items = [{ "date" => "2026-08-01", "direction" => "expense", "amount" => 500, "category_name" => "謎カテゴリ" }]

    _, drafts = ImageImportDraftBuilder.build(items, document: document)
    draft = drafts.first

    expect(draft.category_id).to be_nil
    expect(draft.suggested_category_name).to eq("謎カテゴリ")
  end

  describe "日付の出典と未確定" do
    it "手動指定日付があれば画像内の日付より優先する" do
      items = [{ "date" => "2026-08-01", "raw_date" => "2026年8月1日", "date_year_explicit" => true, "uncertain_fields" => [], "direction" => "expense", "amount" => 100 }]

      _, drafts = ImageImportDraftBuilder.build(items, document: document, manual_date: Date.new(2026, 8, 20))

      expect(drafts.first.date).to eq(Date.new(2026, 8, 20))
    end

    it "手動指定がなければ画像内から読み取った日付を使う" do
      items = [{ "date" => "2026-08-01", "raw_date" => "2026年8月1日", "date_year_explicit" => true, "uncertain_fields" => [], "direction" => "expense", "amount" => 100 }]

      _, drafts = ImageImportDraftBuilder.build(items, document: document)

      expect(drafts.first.date).to eq(Date.new(2026, 8, 1))
    end

    it "日付不明では受付日で補完しない" do
      items = [{ "date" => "not-a-date", "direction" => "expense", "amount" => 100 }]

      _, drafts = ImageImportDraftBuilder.build(items, document: document)

      expect(drafts.first.date).to be_nil
      expect(drafts.first.date_origin).to eq("unresolved")
    end
  end
end
