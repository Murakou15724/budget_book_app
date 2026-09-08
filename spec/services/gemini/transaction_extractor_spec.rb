require 'rails_helper'

RSpec.describe Gemini::TransactionExtractor do
  it "APIキーが未設定の場合はエラー結果を返す(例外を出さない)" do
    allow(Rails.application.credentials).to receive(:dig).with(:gemini, :api_key).and_return(nil)

    result = described_class.new(image_bytes: "dummy", mime_type: "image/png").call

    expect(result.success?).to be false
    expect(result.error_message).to include("APIキー")
    expect(result.items).to eq([])
  end

  describe "responseSchemaに合わない要素への耐性" do
    before do
      allow(Rails.application.credentials).to receive(:dig).with(:gemini, :api_key).and_return("dummy-key")
    end

    def stub_gemini_response(items)
      body = { candidates: [{ content: { parts: [{ text: items.to_json }] } }] }.to_json
      response = Net::HTTPSuccess.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return(body)
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
    end

    it "全要素が想定通りの形であれば成功として全件返す" do
      stub_gemini_response([{ date: "2028-01-01", direction: "expense", amount: 1000 }])

      result = described_class.new(image_bytes: "dummy", mime_type: "image/png").call

      expect(result.success?).to be true
      expect(result.items.size).to eq(1)
    end

    it "形式に合わない要素(Hashでない/必須キー欠落)は除外し、有効な要素だけ返す" do
      stub_gemini_response([
        { date: "2028-01-01", direction: "expense", amount: 1000 },
        "not a hash",
        { memo: "amountが無い" }
      ])

      result = described_class.new(image_bytes: "dummy", mime_type: "image/png").call

      expect(result.success?).to be true
      expect(result.items.size).to eq(1)
      expect(result.items.first["amount"]).to eq(1000)
    end

    it "全要素が形式に合わない場合は失敗として扱い、空のドラフトを作らせない" do
      stub_gemini_response(["not a hash", { memo: "amountが無い" }])

      result = described_class.new(image_bytes: "dummy", mime_type: "image/png").call

      expect(result.success?).to be false
      expect(result.items).to eq([])
    end
  end
end
