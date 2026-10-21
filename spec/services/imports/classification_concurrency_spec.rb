require "rails_helper"
require_relative "../../support/import_concurrency"

RSpec.describe "確認済みルールと自動反映の並行性" do
  self.use_transactional_tests = false
  include ImportConcurrency
  before { record_fixture_ids }
  after { cleanup_fixture_ids }

  def fixtures
    account = Account.create!(name: "68並行元-#{SecureRandom.hex(4)}", kind: :bank)
    category = Category.create!(name: "68並行費-#{SecureRandom.hex(4)}", kind: :expense)
    payment = PaymentMethod.create!(name: "68並行方法-#{SecureRandom.hex(4)}", import_kind: "bank")
    source = import_document(account: account).import_source
    [source, category, payment]
  end

  it "手動新規ルールの同じnonce並行送信で1件だけ作成する" do
    source, category, payment = fixtures
    token = Imports::RuleWriter.form
    values = { import_source_id: source.id, channel: "image", merchant_key: "店", direction: "expense",
      category_id: category.id, payment_method_id: payment.id, account_id: source.account_id, credit_card_status: "not_applicable" }
    results = concurrent(*2.times.map { -> { Imports::RuleWriter.call(attributes: values, token: token, confirmed: "1") } })
    expect(results.map(&:id).uniq.size).to eq(1)
  end

  it "停止commitの後に始まる自動反映を拒否する" do
    source, category, payment = fixtures
    source.update!(image_auto_apply_enabled: true)
    Setting.current.update!(image_import_requires_approval: false)
    rule = confirmed_rule(source: source, category: category, payment: payment)
    draft = ImageImportDraftBuilder.build([extraction_payload], document: import_document(source: source)).last.first
    committed = Queue.new
    results = concurrent(
      -> { ImportClassificationRule.find(rule.id).update!(enabled: false); committed << true },
      -> { Timeout.timeout(15) { committed.pop }; Imports::Applier.call(entry_id: draft.import_entry_id, action: "auto_apply") })
    expect(results.last.status).to eq(:held)
    expect(ImportEntry.find(draft.import_entry_id).target_transaction_id).to be_nil
  end

  %w[general source].each do |setting_type|
    it "#{setting_type}設定の停止commit後に自動反映しない" do
      source, category, payment = fixtures
      source.update!(image_auto_apply_enabled: true)
      setting = Setting.current
      setting.update!(image_import_requires_approval: false)
      confirmed_rule(source: source, category: category, payment: payment)
      draft = ImageImportDraftBuilder.build([extraction_payload], document: import_document(source: source)).last.first
      committed = Queue.new
      results = concurrent(
        -> do
          if setting_type == "general"
            Setting.find(setting.id).update!(image_import_requires_approval: true)
          else
            ImportSource.find(source.id).update!(image_auto_apply_enabled: false)
          end
          committed << true
        end,
        -> { Timeout.timeout(15) { committed.pop }; Imports::Applier.call(entry_id: draft.import_entry_id, action: "auto_apply") })
      expect(results.last.status).to eq(:held)
      expect(ImportEntry.find(draft.import_entry_id).target_transaction_id).to be_nil
      expect(ImportEvent.where(import_entry_id: draft.import_entry_id, kind: "applied")).not_to exist
    end
  end

  it "同じ候補への自動・手動同時反映を取引と確定イベント各1件にする" do
    source, category, payment = fixtures
    source.update!(image_auto_apply_enabled: true)
    Setting.current.update!(image_import_requires_approval: false)
    confirmed_rule(source: source, category: category, payment: payment)
    draft = ImageImportDraftBuilder.build([extraction_payload], document: import_document(source: source)).last.first
    count = Transaction.count
    results = concurrent(*%w[auto_apply approve].map { |action| -> { Imports::Applier.call(entry_id: draft.import_entry_id, action: action) } })
    expect(results.map(&:status)).to contain_exactly(:applied, :already_processed)
    expect(Transaction.count).to eq(count + 1)
    expect(ImportEvent.where(import_entry_id: draft.import_entry_id, kind: "applied").count).to eq(1)
  end
end
