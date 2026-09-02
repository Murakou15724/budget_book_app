require "rails_helper"

RSpec.describe "image imports with multiple files", type: :request do
  def upload_file(name, content_type: "image/png")
    Rack::Test::UploadedFile.new(StringIO.new("dummy image bytes"), content_type, false, original_filename: name)
  end

  it "combines extracted items from multiple images into a single batch" do
    category = Category.create!(name: "食費", kind: :expense, position: 1)

    result1 = Gemini::ExtractionResult.success([
      { "date" => "2026-09-01", "direction" => "expense", "amount" => 1000, "memo" => "画像1の取引" }
    ])
    result2 = Gemini::ExtractionResult.success([
      { "date" => "2026-09-02", "direction" => "expense", "amount" => 2000, "memo" => "画像2の取引" }
    ])
    extractor1 = instance_double(Gemini::TransactionExtractor, call: result1)
    extractor2 = instance_double(Gemini::TransactionExtractor, call: result2)
    allow(Gemini::TransactionExtractor).to receive(:new).and_return(extractor1, extractor2)

    post image_imports_path, params: {
      images: [upload_file("a.png"), upload_file("b.png")]
    }

    expect(response).to redirect_to(image_import_drafts_path(batch_id: ImageImportDraft.order(:id).last.batch_id))
    expect(ImageImportDraft.count).to eq(2)
    expect(ImageImportDraft.pluck(:memo)).to contain_exactly("画像1の取引", "画像2の取引")
  end

  it "skips images with an invalid content type but still processes the valid ones" do
    result = Gemini::ExtractionResult.success([
      { "date" => "2026-09-01", "direction" => "expense", "amount" => 500, "memo" => "有効な画像" }
    ])
    extractor = instance_double(Gemini::TransactionExtractor, call: result)
    allow(Gemini::TransactionExtractor).to receive(:new).and_return(extractor)

    post image_imports_path, params: {
      images: [upload_file("a.png"), upload_file("b.txt", content_type: "text/plain")]
    }

    follow_redirect!
    expect(response.body).to include("処理できませんでした")
    expect(ImageImportDraft.count).to eq(1)
  end

  it "shows an alert when no image is selected" do
    post image_imports_path, params: {}
    expect(response).to redirect_to(new_image_imports_path)
    follow_redirect!
    expect(response.body).to include("画像ファイルを選択してください")
  end
end
