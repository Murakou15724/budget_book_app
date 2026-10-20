require "rails_helper"

RSpec.describe "import history master deletion", type: :request do
  %w[pending applied rejected].each do |state|
    it "#{state}候補だけが参照するマスタも削除せず、理由を表示する" do
      source_account = Account.create!(name: "元口座", kind: :bank)
      account = Account.create!(name: "反映口座", kind: :cash)
      category = Category.create!(name: "食費", kind: :expense)
      budget = category.category_monthly_budgets.create!(year: 2026, month: 10, budget: 1000)
      payment = PaymentMethod.create!(name: "現金")
      document = import_document(account: source_account)
      draft = tracked_draft(document: document, account: account, category: category, payment_method: payment,
        date: Date.new(2026, 10, 1), amount: 500)
      draft.import_entry.update!(state: state)
      [[category_path(category), category], [payment_method_path(payment), payment], [account_path(account), account],
        [account_path(source_account), source_account]].each do |path, master|
        delete path
        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(response.body).to include("取込候補・履歴で使用中")
        expect(master.class.exists?(master.id)).to be(true)
      end
      expect(budget.reload.budget).to eq(1000)
      expect(draft.reload).to be_persisted
    end
  end

  it "未使用のマスタは従来どおり削除可能" do
    category = Category.create!(name: "未使用", kind: :expense)
    delete category_path(category)
    expect(Category.exists?(category.id)).to be(false)
  end
end
