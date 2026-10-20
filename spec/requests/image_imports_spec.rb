require "rails_helper"

RSpec.describe "image imports with multiple files", type: :request do
  let(:source) { import_document.import_source }

  def upload_file(name, content_type: "image/png")
    Rack::Test::UploadedFile.new(StringIO.new("dummy image bytes #{name}"), content_type, false, original_filename: name)
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
      import_source_id: source.id, images: [upload_file("a.png"), upload_file("b.png")]
    }

    ids = ImageImportDraft.order(:id).map { |d| d.import_entry.import_document_id }
    expect(response).to redirect_to(image_import_drafts_path(document_ids: ids, image_numbers: ids.each_with_index.to_h { |id, index| [id.to_s, [index + 1]] }))
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
      import_source_id: source.id, images: [upload_file("a.png"), upload_file("b.txt", content_type: "text/plain")]
    }

    follow_redirect!
    expect(response.body).to include("処理できませんでした")
    expect(ImageImportDraft.count).to eq(1)
  end

  it "returns a friendly error instead of a 500 when images param is not an uploaded file" do
    post image_imports_path, params: { import_source_id: source.id, images: ["not a file"] }

    expect(response).to redirect_to(new_image_imports_path)
    follow_redirect!
    expect(response.body).to include("読み取れませんでした")
  end

  it "shows an alert when no image is selected" do
    post image_imports_path, params: {}
    expect(response).to redirect_to(new_image_imports_path)
    follow_redirect!
    expect(response.body).to include("画像ファイルを選択してください")
  end

  it "送信順・途中の形式エラー・既存画像再送・同一画像の重複指定でも番号を維持する" do
    result = Gemini::ExtractionResult.success([{ "date" => "2026-10-01", "amount" => 500, "direction" => "expense" }])
    allow(Gemini::TransactionExtractor).to receive(:new).and_return(instance_double(Gemini::TransactionExtractor, call: result))
    post image_imports_path, params: { import_source_id: source.id, images: [upload_file("old.png")] }
    old_document = ImageImportDraft.last.import_entry.import_document
    post image_imports_path, params: { import_source_id: source.id,
      images: [upload_file("new.png"), upload_file("invalid.txt", content_type: "text/plain"), upload_file("old.png"), upload_file("new.png")] }
    follow_redirect!
    sections = Nokogiri::HTML(response.body).css("section.entry-card")
    expect(sections.size).to eq(2)
    expect(sections[0].at_css("h2").text).to include("画像1・4")
    expect(sections[1].at_css("h2").text).to include("画像3", "取込文書 ##{old_document.id}")
    expect(response.body).to include("画像2:")
  end
end
