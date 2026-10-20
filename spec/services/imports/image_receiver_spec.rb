require "rails_helper"

RSpec.describe Imports::ImageReceiver do
  let(:source) { import_document.import_source }
  let(:item) { { "date" => "2026-10-01", "amount" => 1000, "direction" => "expense", "memo" => "店" } }

  def upload(bytes = "image", name = "a.png")
    Rack::Test::UploadedFile.new(StringIO.new(bytes), "image/png", false, original_filename: name)
  end

  def receive_images(images, manual_date: nil)
    described_class.call(source: source, images: images, manual_date: manual_date)
  end

  before do
    allow(Gemini::TransactionExtractor).to receive(:new).and_return(instance_double(Gemini::TransactionExtractor,
      call: Gemini::ExtractionResult.success([item])))
  end

  it "同じ画像の別名再送・同時指定は同じ文書・候補を返しAIを呼び直さない" do
    result = receive_images([upload, upload("image", "b.png")])
    expect(result.documents.size).to eq(1)
    expect { receive_images([upload("image", "c.png")]) }.not_to change(ImageImportDraft, :count)
    expect(Gemini::TransactionExtractor).to have_received(:new).once
    expect(result.documents.first.import_entries.count).to eq(1)
  end

  it "初回手動日付と受付日を固定し、再送日付を遡及適用しない" do
    result = receive_images([upload], manual_date: Date.new(2026, 8, 1))
    receive_images([upload], manual_date: Date.new(2026, 9, 1))
    expect(result.documents.first.reload.manual_date).to eq(Date.new(2026, 8, 1))
    expect(result.documents.first.import_entries.first.image_import_draft.date).to eq(Date.new(2026, 8, 1))
  end

  it "0行成功と失敗を画像単位で記録し、成功済みは再解析しない" do
    success = instance_double(Gemini::TransactionExtractor, call: Gemini::ExtractionResult.success([]))
    failure = instance_double(Gemini::TransactionExtractor, call: Gemini::ExtractionResult.failure("秘密を含むエラー"))
    allow(Gemini::TransactionExtractor).to receive(:new).and_return(success, failure)
    result = receive_images([upload("one"), upload("two")])
    expect(result.documents.map(&:state)).to eq(%w[extracted failed])
    expect(ImportEvent.all.map(&:details).to_json).not_to include("秘密")
    allow(Gemini::TransactionExtractor).to receive(:new).and_return(success)
    result = receive_images([upload("one"), upload("two")])
    expect(result.documents.map(&:state)).to eq(%w[extracted extracted])
  end

  it "抽出保存の途中失敗は文書全行rollbackし再アップロードで再開する" do
    allow(Gemini::TransactionExtractor).to receive(:new).and_return(instance_double(Gemini::TransactionExtractor,
      call: Gemini::ExtractionResult.success([item, item.merge("amount" => 2000)])))
    allow(Imports::EntryRecorder).to receive(:call).and_wrap_original do |original, **args|
      raise "injected" if args[:row_number] == 2
      original.call(**args)
    end
    expect { receive_images([upload]) }.not_to change(ImportEntry, :count)
    expect(ImportDocument.where(channel: "image").last.state).to eq("failed")
    allow(Imports::EntryRecorder).to receive(:call).and_call_original
    expect { receive_images([upload]) }.to change(ImportEntry, :count).by(2)
  end

  it "設定変更後の既存画像再送では過去候補を自動反映しない" do
    receive_images([upload])
    Setting.current.update!(image_import_requires_approval: false)
    expect { receive_images([upload]) }.not_to change(Transaction, :count)
  end

  it "承認不要設定でも新規だけを反映し、別画像の類似候補は停止する" do
    category = Category.create!(name: "画像分類", kind: :expense)
    payment = PaymentMethod.create!(name: "画像方法")
    valid_item = item.merge("category_name" => category.name, "payment_method_name" => payment.name, "account_name" => source.account.name)
    allow(Gemini::TransactionExtractor).to receive(:new).and_return(instance_double(Gemini::TransactionExtractor,
      call: Gemini::ExtractionResult.success([valid_item])))
    Setting.current.update!(image_import_requires_approval: false)
    first = receive_images([upload("first")])
    second = receive_images([upload("overlap")])
    expect(first.applied_count).to eq(1)
    expect(second.applied_count).to eq(0)
    expect(second.documents.first.import_entries.first.state).to eq("held")
    expect(Transaction.count).to eq(1)
  end
end
