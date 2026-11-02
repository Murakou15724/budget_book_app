require "rails_helper"
require_relative "../../support/paypay_csv_fixtures"

RSpec.describe Imports::CsvSummary do
  before { setup_csv_source }

  it "assigns each row to one of six groups and separates raw amounts from immutable applied event amounts" do
    rows = [csv_row, csv_row(取引番号: "manual", 取引先: "架空手動", 出金金額（円）: "12"),
      csv_row(取引番号: "pending", 取引先: "架空不明", 出金金額（円）: "15"), csv_row,
      csv_row(取引番号: "special", 取引内容: "チャージ", 出金金額（円）: "14"),
      csv_row(取引番号: "error", 取引日: "", 出金金額（円）: "13")]
    document = receive_csv(rows).document
    manual = document.import_entries.find_by(row_number: 3)
    expect(Imports::Applier.call(entry_id: manual.id, action: "approve", attributes: { category_id: @category.id, amount: 20 }).status).to eq(:applied)
    summary = described_class.call(document: document)
    expect(summary[:count]).to eq(6)
    expect(summary[:groups].values.map { |g| g[:count] }).to eq([1, 1, 1, 1, 1, 1])
    expect(summary[:raw][:outgoing]).to eq(2054)
    expect(summary[:groups]["normal"][:outgoing]).to eq(20)
    expect(summary[:groups]["automatic"][:outgoing]).to eq(1000)
    expect(summary[:groups].values.sum { |g| g[:incoming] }).to eq(0)
    manual.image_import_draft.update!(amount: 999)
    expect(described_class.call(document: document)[:groups]["normal"][:outgoing]).to eq(20)
  end

  it "keeps unresolved references pending, labels rejected representatives, and excludes foreign and unreadable amounts" do
    Setting.current.update!(image_import_requires_approval: true)
    document = receive_csv([csv_row] * 2 + [csv_row(取引番号: "foreign", 通貨: "USD"), csv_row(取引番号: "unknown", 出金金額（円）: "1.2")]).document
    summary = described_class.call(document: document)
    expect(summary[:groups]["pending"][:count]).to eq(2)
    expect(summary[:raw][:unknown_amount_count]).to eq(2)
    representative = document.import_entries.order(:row_number).first
    Imports::Applier.call(entry_id: representative.id, action: "reject")
    summary = described_class.call(document: document)
    expect(summary[:groups]["duplicate"][:details]).to include("reference_rejected" => 1)
    expect(summary[:groups]["excluded"][:count]).to eq(2)
    expect(summary[:groups]["error"][:count]).to eq(1)
  end
end
