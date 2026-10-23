require "rails_helper"
require_relative "../../support/import_concurrency"

RSpec.describe "image receiver concurrency", type: :model do
  self.use_transactional_tests = false
  include ImportConcurrency

  before do
    record_fixture_ids
    Setting.current.update!(image_import_requires_approval: false)
  end
  after { cleanup_fixture_ids }

  def upload(bytes)
    Rack::Test::UploadedFile.new(StringIO.new(bytes), "image/png", false, original_filename: "image.png")
  end

  def fixture_item
    account = Account.create!(name: "並行画像口座-#{SecureRandom.hex(4)}", kind: :bank)
    category = Category.create!(name: "並行画像分類-#{SecureRandom.hex(4)}", kind: :expense)
    method = PaymentMethod.create!(import_kind: "bank", name: "並行画像方法-#{SecureRandom.hex(4)}")
    [account, extraction_payload(amount: 500).merge("memo" => "店",
      "category_name" => category.name, "payment_method_name" => method.name, "account_name" => account.name)]
  end

  def enable_source(source, item)
    source.update!(image_auto_apply_enabled: true)
    confirmed_rule(source: source, category: Category.find_by!(name: item["category_name"]), payment: PaymentMethod.find_by!(name: item["payment_method_name"]))
  end

  it "同一画像の並行再送は外部応答が二つでも文書・候補・取引を一つだけ確定する" do
    account, item = fixture_item
    source = import_document(account: account).import_source
    enable_source(source, item)
    arrived = Queue.new
    release = Queue.new
    allow(Gemini::TransactionExtractor).to receive(:new) do
      extractor = instance_double(Gemini::TransactionExtractor)
      allow(extractor).to receive(:call) do
        arrived << true
        Timeout.timeout(15) { release.pop }
        Gemini::ExtractionResult.success([item])
      end
      extractor
    end
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Imports::ImageReceiver.call(source: ImportSource.find(source.id), images: [upload("same")], manual_date: nil)
        end
      end
    end
    Timeout.timeout(15) { 2.times { arrived.pop } }
    2.times { release << true }
    results = threads.map { |thread| Timeout.timeout(20) { thread.value } }
    expect(results.map { |r| r.documents.first.id }.uniq.size).to eq(1)
    document = results.first.documents.first
    expect(document.reload.state).to eq("extracted")
    expect(document.import_entries.count).to eq(1)
    expect(document.import_events.where(kind: "extracted").count).to eq(1)
    expect(Transaction.where(account: account).count).to eq(1)
  ensure
    threads&.each { |t| t.kill.join if t.alive? }
  end

  it "異文書・別sourceの同時取込で先行を反映し後発を類似保留にする" do
    account, item = fixture_item
    first_source = import_document(account: account).import_source
    second_source = import_document(account: account).import_source
    enable_source(first_source, item)
    enable_source(second_source, item)
    arrived = Queue.new
    release = Queue.new
    allow(Gemini::TransactionExtractor).to receive(:new) do |image_bytes:, **|
      extractor = instance_double(Gemini::TransactionExtractor)
      allow(extractor).to receive(:call) do
        if image_bytes == "second"
          arrived << true
          Timeout.timeout(15) { release.pop }
        end
        Gemini::ExtractionResult.success([item])
      end
      extractor
    end
    later = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Imports::ImageReceiver.call(source: ImportSource.find(second_source.id), images: [upload("second")], manual_date: nil)
      end
    end
    Timeout.timeout(15) { arrived.pop }
    first = Imports::ImageReceiver.call(source: first_source, images: [upload("first")], manual_date: nil)
    release << true
    second = Timeout.timeout(20) { later.value }
    expect(first.applied_count).to eq(1)
    expect(second.applied_count).to eq(0)
    expect(second.documents.first.import_entries.first.state).to eq("held")
    expect(second.documents.first.import_entries.first.reason_code).to eq("similar_candidates")
    expect(Transaction.where(account: account).count).to eq(1)
  ensure
    later.kill.join if later&.alive?
  end

  it "先行成功を遅れて届いた抽出失敗が上書きしない" do
    account, item = fixture_item
    source = import_document(account: account).import_source
    enable_source(source, item)
    arrived = Queue.new
    release = Queue.new
    slow = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        extractor = instance_double(Gemini::TransactionExtractor)
        allow(extractor).to receive(:call) do
          arrived << true
          Timeout.timeout(15) { release.pop }
          Gemini::ExtractionResult.failure("失敗")
        end
        allow(Gemini::TransactionExtractor).to receive(:new).and_return(extractor)
        Imports::ImageReceiver.call(source: ImportSource.find(source.id), images: [upload("same")], manual_date: nil)
      end
    end
    Timeout.timeout(15) { arrived.pop }
    success = instance_double(Gemini::TransactionExtractor, call: Gemini::ExtractionResult.success([item]))
    allow(Gemini::TransactionExtractor).to receive(:new).and_return(success)
    first = Imports::ImageReceiver.call(source: source, images: [upload("same")], manual_date: nil)
    release << true
    Timeout.timeout(20) { slow.value }
    document = first.documents.first.reload
    expect(document.state).to eq("extracted")
    expect(document.error_code).to be_nil
    expect(document.import_entries.count).to eq(1)
    expect(Transaction.where(account: account).count).to eq(1)
  ensure
    slow.kill.join if slow&.alive?
  end
end
