require 'rails_helper'

RSpec.describe QuickEntryTemplate, type: :model do
  let(:category) { Category.create!(kind: :expense, name: "食費") }
  let(:payment_method) { PaymentMethod.create!(name: "現金") }
  let(:account) { Account.create!(name: "財布", kind: :cash) }

  def build_template(attrs = {})
    QuickEntryTemplate.new(
      { name: "コンビニ", direction: :expense, category: category, payment_method: payment_method, account: account }.merge(attrs)
    )
  end

  it "有効な属性であれば保存できる" do
    expect(build_template).to be_valid
  end

  it "nameが重複していると保存できない" do
    build_template.save!
    expect(build_template(name: "コンビニ")).not_to be_valid
  end

  it "nameが未入力だと保存できない" do
    expect(build_template(name: nil)).not_to be_valid
  end

  it "参照しているcategoryが削除されるとエラーになる" do
    build_template.save!
    expect(category.destroy).to be false
    expect(category.errors[:base]).to be_present
  end

  it "参照しているpayment_methodが削除されるとエラーになる" do
    build_template.save!
    expect(payment_method.destroy).to be false
  end

  it "参照しているaccountが削除されるとエラーになる" do
    build_template.save!
    expect(account.destroy).to be false
  end
end
