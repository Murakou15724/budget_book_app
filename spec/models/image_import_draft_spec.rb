require 'rails_helper'

RSpec.describe ImageImportDraft, type: :model do
  it "batch_idが必須" do
    draft = ImageImportDraft.new(batch_id: nil)
    expect(draft).not_to be_valid
  end

  describe "#resolved?" do
    let(:category) { Category.create!(kind: :expense, name: "食費") }
    let(:payment_method) { PaymentMethod.create!(name: "現金") }
    let(:account) { Account.create!(name: "財布", kind: :cash) }

    it "category/payment_method/account/amountが揃っていればtrue" do
      draft = ImageImportDraft.new(batch_id: "b1", category: category, payment_method: payment_method, account: account, amount: 1000)
      expect(draft.resolved?).to be true
    end

    it "いずれか欠けていればfalse" do
      draft = ImageImportDraft.new(batch_id: "b1", category: category, payment_method: payment_method, account: nil, amount: 1000)
      expect(draft.resolved?).to be false
    end

    it "金額が未取得(nil)または0以下ならfalse" do
      draft = ImageImportDraft.new(batch_id: "b1", category: category, payment_method: payment_method, account: account, amount: nil)
      expect(draft.resolved?).to be false

      draft.amount = 0
      expect(draft.resolved?).to be false
    end
  end
end
