require "rails_helper"
require_relative "../../support/paypay_csv_fixtures"
require_relative "../../support/import_concurrency"

RSpec.describe "CSV import concurrency", type: :model do
  include ImportConcurrency
  self.use_transactional_tests = false

  before do
    record_fixture_ids
    setup_csv_source
  end
  after { cleanup_fixture_ids }

  it "serializes simultaneous identical files without duplicate documents/transactions" do
    results = concurrent(-> { receive_csv }, -> { receive_csv })
    expect(results.flat_map(&:processing_errors)).to eq([])
    expect(results.map { |r| r.document.id }.uniq.size).to eq(1)
    expect(results.sum(&:applied_count)).to eq(1)
    expect(ImportIdentity.where(import_source: @source).count).to eq(1)
    expect(Transaction.where(account: @wallet).count).to eq(1)
  end

  it "serializes overlapping periods on the shared ledger" do
    rows = [csv_row, csv_row(取引番号: "second", 出金金額（円）: "2")]
    results = concurrent(-> { receive_csv(rows) }, -> { receive_csv(rows.reverse, bom: true) })
    expect(results.flat_map(&:processing_errors)).to eq([])
    expect(Transaction.where(account: @wallet).count).to eq(2)
    expect(ImportEntry.where(import_document_id: results.map { |r| r.document.id }).count).to eq(4)
    expect(ImportEntry.where(import_document_id: results.map { |r| r.document.id }, state: "reference").count).to eq(2)
  end

  it "serializes CSV with an image/manual candidate for the same account, amount and date" do
    draft = ImageImportDraftBuilder.build([extraction_payload(merchant: "架空店")], document: import_document(account: @wallet)).last.first
    draft.update!(category: @category, payment_method: @csv_routes["PayPay残高"].payment_method, account: @wallet)
    results = concurrent(-> { receive_csv }, -> { Imports::Applier.call(entry_id: draft.import_entry_id, action: "approve") })
    expect(results.first.processing_errors).to eq([])
    expect(Transaction.where(account: @wallet, amount: 1000).count).to be <= 1
    expect(results.first.document.import_entries.first.state).to eq("held")
  end

  it "makes automatic application and route stopping atomic and refuses future application after stopping" do
    results = concurrent(-> { receive_csv }, -> { @csv_routes["PayPay残高"].update!(enabled: false) })
    result = results.first
    expect(result.processing_errors).to eq([])
    expect(Transaction.where(account: @wallet).count).to be <= 1
    entry = result.document.import_entries.first
    count = Transaction.count
    expect(Imports::Applier.call(entry_id: entry.id, action: "auto_apply").status).to be_in([:held, :already_processed])
    expect(Transaction.count).to eq(count)
  end

  it "serializes route creation for the same exact method with a unique key" do
    values = { import_source_id: @source.id, account_id: @bank.id, payment_method_id: @csv_routes["架空銀行"].payment_method_id,
      source_method: "同一新規方法", credit_card_status: "not_applicable" }
    operation = lambda do
      ImportPaymentRoute.create!(values)
      :saved
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      :duplicate
    end
    expect(concurrent(operation, operation).sort).to eq([:duplicate, :saved])
    expect(@source.import_payment_routes.where(source_method: "同一新規方法").count).to eq(1)
  end
end
