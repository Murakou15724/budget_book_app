require 'rails_helper'

RSpec.describe Gemini::TransactionExtractor do
  it "APIキーが未設定の場合はエラー結果を返す(例外を出さない)" do
    allow(Rails.application.credentials).to receive(:dig).with(:gemini, :api_key).and_return(nil)

    result = described_class.new(image_bytes: "dummy", mime_type: "image/png").call

    expect(result.success?).to be false
    expect(result.error_message).to include("APIキー")
    expect(result.items).to eq([])
  end
end
