require "rails_helper"
require_relative "../../support/paypay_csv_fixtures"

RSpec.describe Imports::PaypayCsvParser do
  def parse(row = csv_row, **options)
    described_class.call(bytes: csv_bytes([row], **options)).rows.first
  end

  it "keeps all raw cells, long zero-prefixed case-sensitive IDs, JST seconds, quotes and newlines" do
    raw = csv_row(取引先: "架空,\"店\"\n支店", 取引番号: "000Aa" * 14_000)
    row = parse(raw)
    expect(row.raw).to eq(raw)
    expect(row.external_id).to eq(raw["取引番号"])
    expect(row.payload.values_at("amount", "date", "occurred_at")).to eq([1000, "2026-10-01", "2026-10-01T12:34:56+09:00"])
    expect(row.payload["csv_physical_line"]).to eq(3)
    expect(row.errors).to be_empty
  end

  it "treats BOM, CRLF and reordered headers as the same cells and source digest" do
    rows = [parse, parse(csv_row, bom: true, row_sep: "\r\n", headers: described_class::HEADERS.reverse)]
    expect(rows.map { |row| Imports::Fingerprint.digest(Imports::Fingerprint.source_payload(row.payload)) }.uniq.size).to eq(1)
    expect(rows.map(&:raw).uniq.size).to eq(1)
  end

  it "accepts only the 13 exact distinct headers" do
    [described_class::HEADERS.drop(1), described_class::HEADERS + ["追加"], ["取引日"] + described_class::HEADERS.drop(1).map { "取引日" }].each do |headers|
      expect { described_class.call(bytes: csv_bytes([], headers: headers)) }.to raise_error(described_class::FileError) { |e| expect(e.code).to eq("csv_headers") }
    end
  end

  it "rejects empty, BOM-only, invalid UTF-8, CP932, NUL and malformed/blank/short/long records" do
    header = csv_bytes([])
    inputs = ["", "\uFEFF", "\xFF".b, csv_bytes.encode("Windows-31J", undef: :replace), header + "\0", csv_bytes + '"open', csv_bytes + "\n", csv_bytes + "a,b\n", csv_bytes + (["a"] * 14).join(",")]
    inputs.each { |bytes| expect { described_class.call(bytes: bytes) }.to raise_error(described_class::FileError) }
    expect(described_class.call(bytes: header).rows).to eq([])
  end

  it "checks the byte and logical record limits before accepting any rows" do
    expect(described_class.call(bytes: csv_bytes(Array.new(1000) { csv_row })).rows.size).to eq(1000)
    expect { described_class.call(bytes: csv_bytes(Array.new(1001) { csv_row })) }.to raise_error(described_class::FileError) { |e| expect(e.code).to eq("csv_too_many_rows") }
    base = csv_bytes([csv_row(取引番号: "x")])
    limit = described_class::MAX_BYTES
    [limit - 1, limit].each do |size|
      bytes = csv_bytes([csv_row(取引番号: "x" * (size - base.bytesize + 1))])
      expect(bytes.bytesize).to eq(size)
      expect(described_class.call(bytes: bytes).rows.size).to eq(1)
    end
    expect { described_class.call(bytes: "x" * (limit + 1)) }.to raise_error(described_class::FileError) { |e| expect(e.code).to eq("csv_too_large") }
  end

  it "validates integer syntax, both directions, range, and preserves arbitrarily large decimal strings" do
    %w[0 -1 1.2 1e3 １２３ 01 1,00 ,100].each { |value| expect(parse(csv_row(出金金額（円）: value)).errors).not_to be_empty }
    expect(parse(csv_row(入金金額（円）: "1")).errors).to include("csv_amount_direction")
    [1, 2**31 - 1].each { |value| expect(parse(csv_row(出金金額（円）: value.to_s)).draft_attributes[:amount]).to eq(value) }
    [2**31, 18_446_744_073_709_551_617, "9" * 400].each do |value|
      row = parse(csv_row(出金金額（円）: value.to_s))
      expect(row.errors).to include("csv_amount_range")
      expect(row.draft_attributes[:amount]).to be_nil
      expect(row.payload["csv_amounts"]["outgoing"]).to eq(value.to_s)
      expect(JSON.parse(JSON.generate(row.payload))["amount"]).to eq(value.to_s)
    end
    income = parse(csv_row(出金金額（円）: "ー", 入金金額（円）: "2,000", 取引内容: "給与"))
    expect(income.draft_attributes.values_at(:amount, :direction, :transaction_kind)).to eq([2000, "income", "normal"])
  end

  it "requires a complete real JST timestamp within 2000..2099" do
    ["", "10/01 12:00", "2026/02/29 12:00", "2026/10/01 24:00", "2100/01/01 00:00", "2026/1/01 12:00"].each do |date|
      row = parse(csv_row(取引日: date))
      expect(row.errors).to include("csv_date")
      expect(row.draft_attributes[:date_origin]).to eq("unresolved")
    end
    %w[2024/02/29 2026/10/31 2026/11/01 2026/12/31 2027/01/01].each do |date|
      expect(parse(csv_row(取引日: date + " 00:00")).payload["date"]).to eq(date.tr("/", "-"))
    end
  end

  it "holds special, foreign, points and conflicting content without losing any cells" do
    %w[チャージ 送金 受け取り 銀行口座への出金 カード引落 返金 取消 手数料 ポイント 支払い受付 未知].each do |content|
      row = parse(csv_row(取引内容: content))
      expect(row.holds).to include("csv_special")
      expect(row.raw["取引内容"]).to eq(content)
    end
    [csv_row(取引番号: "lp-0001"), csv_row(取引方法: "残高+ポイント"), csv_row(通貨: "USD"), csv_row(海外出金金額: "1"), csv_row(変換レート（円）: "150"), csv_row(利用国: "US")].each do |raw|
      expect(parse(raw).holds).not_to be_empty
    end
    expect(parse(csv_row(取引先: "返金店")).draft_attributes[:transaction_kind]).to eq("refund")
    expect(parse(csv_row(取引内容: "給与")).errors).to include("csv_content_direction")
    expect(parse(csv_row(取引番号: " \t")).external_id).to be_nil
  end
end
