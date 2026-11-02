require "rails_helper"
require_relative "../support/paypay_csv_fixtures"

RSpec.describe ImportPaymentRoute do
  before { setup_csv_source }

  it "validates source, exact immutable keys, types, status, digest uniqueness, stopping and deletion restrictions" do
    route = @csv_routes["PayPay残高"]
    expect(route.version).to eq(1)
    expect(route.update(enabled: false)).to be(true)
    expect(route.version).to eq(2)
    expect(route.update(source_method: "他")).to be(false)
    route.reload
    expect(route.update(account: @card)).to be(false)
    expect(route.destroy).to be(false)
    duplicate = route.dup
    expect(duplicate).not_to be_valid
    expect(@csv_routes["PayPayクレジット"].update(credit_card_status: "not_applicable")).to be(false)
    %w[ポイント 残高+カード].each do |method|
      expect(@source.import_payment_routes.new(source_method: method, account: @bank, payment_method: @csv_routes["架空銀行"].payment_method, credit_card_status: "not_applicable")).not_to be_valid
    end
  end

  it "retains byte-sensitive methods and detects a digest collision instead of assigning an account" do
    route = @csv_routes["架空銀行"]
    entry = receive_csv([csv_row(取引方法: "Unknown")]).document.import_entries.first
    allow(Digest::SHA256).to receive(:hexdigest).with("Unknown".b).and_return(route.source_method_digest)
    expect(Imports::SourceRoute.resolve(entry: entry).reasons).to eq(["csv_route_collision"])
  end

  it "restricts masters referenced only by routes and applies optimistic locking" do
    route = @source.import_payment_routes.create!(source_method: "OnlyRoute", account: Account.create!(name: "専用", kind: :cash),
      payment_method: PaymentMethod.create!(name: "専用現金", import_kind: "cash"), credit_card_status: "not_applicable")
    expect(route.account.destroy).to be(false)
    expect(route.payment_method.destroy).to be(false)
    stale = described_class.find(route.id)
    route.update!(enabled: true)
    expect { stale.update!(enabled: true) }.to raise_error(ActiveRecord::StaleObjectError)
  end

  it "rejects rules that inject a route from another source or mismatch its outputs/channel" do
    rule = ImportClassificationRule.find_by(import_payment_route: @csv_routes["PayPay残高"])
    expect(rule.update(channel: "image")).to be(false)
    rule.reload
    expect(rule.update(account: @bank)).to be(false)
    rule.reload
    another = ImportSource.create!(service_key: "paypay", account: @wallet, name: "別利用者")
    expect(rule.update(import_source: another)).to be(false)
  end
end
