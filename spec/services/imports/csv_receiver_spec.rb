require "rails_helper"
require_relative "../../support/paypay_csv_fixtures"

RSpec.describe Imports::CsvReceiver do
  before { setup_csv_source }

  it "automatically applies ten configured payments/income on distinct routes, without per-row selections" do
    rows = 10.times.map do |index|
      method = @csv_routes.keys[index % 3]
      income = index % 4 == 0 && method != "PayPayクレジット"
      csv_row(取引番号: "000-#{index}", 取引方法: method, 出金金額（円）: income ? "-" : (index + 1).to_s,
        入金金額（円）: income ? (index + 1).to_s : "-", 取引内容: income ? "給与" : "支払い", 取引先: income ? "架空勤務先" : "架空店")
    end
    result = receive_csv(rows)
    expect(result.processing_errors).to eq([])
    expect(result.applied_count).to eq(10)
    expect(Transaction.count).to eq(10)
    result.document.import_entries.includes(:target_transaction).each do |entry|
      route = @csv_routes.fetch(entry.payload["source_method"])
      expect(entry.target_transaction.attributes.slice(*ImportPaymentRoute::OUTPUT_KEYS)).to eq(route.attributes.slice(*ImportPaymentRoute::OUTPUT_KEYS))
    end
    expect(receive_csv(rows).applied_count).to eq(0)
    expect(Transaction.count).to eq(10)
  end

  it "keeps approval and CSV permission independent from image permission and never applies old rows retroactively" do
    [[true, true], [true, false], [false, false]].each_with_index do |(approval, csv_allowed), index|
      Setting.current.update!(image_import_requires_approval: approval)
      @source.update!(csv_auto_apply_enabled: csv_allowed, image_auto_apply_enabled: true)
      rows = [csv_row(取引番号: "gate-#{index}", 出金金額（円）: (index + 10).to_s)]
      expect(receive_csv(rows).applied_count).to eq(0)
      Setting.current.update!(image_import_requires_approval: false)
      @source.update!(csv_auto_apply_enabled: true)
      expect(receive_csv(rows).applied_count).to eq(0)
    end
    expect(Transaction.count).to eq(0)
  end

  it "requires one matching CSV rule for the same source, method, merchant and direction" do
    rule = ImportClassificationRule.find_by(import_payment_route: @csv_routes["PayPay残高"], direction: "expense")
    rule.update!(enabled: false)
    confirmed_rule(source: @source, category: @category, payment: @csv_routes["架空銀行"].payment_method, merchant: "架空店")
    expect(receive_csv.applied_count).to eq(0)
    rule.update!(enabled: true)
    duplicate = rule.dup
    duplicate.creation_nonce = SecureRandom.uuid
    duplicate.save!
    result = receive_csv([csv_row(取引番号: "ambiguous")])
    expect(result.applied_count).to eq(0)
    expect(result.document.import_entries.first.image_import_draft.rule_decision["reason_codes"]).to include("rule_ambiguous")
  end

  it "records bad/special rows and processes valid rows in the same file" do
    rows = [csv_row, csv_row(取引番号: "bad", 取引日: "", 出金金額（円）: "1.2"), csv_row(取引番号: "special", 取引内容: "チャージ", 出金金額（円）: "30")]
    result = receive_csv(rows)
    expect(result.applied_count).to eq(1)
    expect(result.document.import_entries.count).to eq(3)
    expect(receive_csv(rows).applied_count).to eq(0)
    expect(Transaction.count).to eq(1)
    groups = Imports::CsvSummary.call(document: result.document)[:groups]
    expect(groups.transform_values { |g| g[:count] }).to include("automatic" => 1, "error" => 1, "excluded" => 1)
  end

  it "holds missing/stopped/mixed/points routes and refuses creation through distinct" do
    @csv_routes["PayPay残高"].update!(enabled: false)
    ["PayPay残高", "未知経路", "PayPay残高+ポイント"].each_with_index do |method, index|
      entry = receive_csv([csv_row(取引番号: "route-#{index}", 取引方法: method)]).document.import_entries.first
      draft = entry.image_import_draft
      Imports::CandidateConfirmation.apply(draft, attributes: { account_id: @wallet.id, payment_method_id: @csv_routes["PayPay残高"].payment_method_id, category_id: @category.id }).save!
      result = Imports::Applier.call(entry_id: entry.id, action: "distinct", review_token: review_token(entry, "distinct"))
      expect(result.status).to eq(:held)
    end
    expect(Transaction.count).to eq(0)
  end

  it "preserves huge amounts/IDs through both DB JSON adapters, rereads, summaries, digests and resends" do
    identifiers = ["0" * 65_535, "0" * 65_536, "あ" * 22_000]
    huge = [18_446_744_073_709_551_617.to_s, "9" * 400, (2**31).to_s]
    rows = identifiers.zip(huge).map { |id, amount| csv_row(取引番号: id, 出金金額（円）: amount) } + [csv_row(取引番号: "valid", 出金金額（円）: "77")]
    result = receive_csv(rows)
    expect(result.applied_count).to eq(1)
    entries = result.document.import_entries.order(:row_number).to_a
    entries.first(3).each_with_index do |entry, index|
      expect(entry.import_identity.external_id).to eq(identifiers[index])
      expect(entry.payload["csv_amounts"]["outgoing"]).to eq(huge[index])
      expect(entry.payload["amount"]).to eq(huge[index])
      expect(entry.payload_digest).to eq(Imports::Fingerprint.digest(Imports::Fingerprint.source_payload(entry.payload)))
    end
    expect(Imports::CsvSummary.call(document: result.document)[:raw][:outgoing]).to eq(huge.sum { |v| Integer(v, 10) } + 77)
    expect(receive_csv(rows.reverse).document.import_entries.where(state: "reference").count).to eq(4)
    expect(Transaction.count).to eq(1)
  end

  it "references identical cells across formatting/overlap and creates a correction when one cell or method changes" do
    first = receive_csv.document.import_entries.first
    other = receive_csv([csv_row], bom: true, row_sep: "\r\n", headers: Imports::PaypayCsvParser::HEADERS.reverse).document.import_entries.first
    expect(other.reference_entry_id).to eq(first.id)
    changed = receive_csv([csv_row(取引方法: "架空銀行")]).document.import_entries.first
    expect(changed.classification).to eq("correction")
    expect(changed.import_identity_id).to eq(first.import_identity_id)
    expect(Imports::Applier.call(entry_id: changed.id, action: "approve").status).to eq(:held)
    expect(Transaction.count).to eq(1)
  end

  it "holds a different ID with similar manual/image/CSV entries and in-file duplicates" do
    receive_csv
    expect(receive_csv([csv_row(取引番号: "another")]).document.import_entries.first.reason_code).to eq("similar_candidates")
    rows = [csv_row(取引番号: "infile", 出金金額（円）: "33"), csv_row(取引番号: "infile2", 出金金額（円）: "33")]
    expect(receive_csv(rows).applied_count).to eq(0)
    expect(receive_csv([csv_row(取引番号: "same", 出金金額（円）: "44")] * 2).document.import_entries.where(state: "reference").count).to eq(1)
  end

  it "rolls all candidate writes back, marks a failed document, and accepts a retry" do
    calls = 0
    allow(Imports::EntryRecorder).to receive(:call).and_wrap_original do |original, **args|
      calls += 1
      raise "simulated failure" if calls == 2
      original.call(**args)
    end
    rows = [csv_row, csv_row(取引番号: "second", 出金金額（円）: "3")]
    result = receive_csv(rows)
    expect(result.processing_errors).to include("processing_failed")
    expect(result.document.reload.state).to eq("failed")
    expect(result.document.import_entries.count).to eq(0)
    expect(ImportIdentity.count).to eq(0)
    expect(Transaction.count).to eq(0)
    allow(Imports::EntryRecorder).to receive(:call).and_call_original
    expect(receive_csv(rows).applied_count).to eq(2)
  end

  it "continues after auto failures, exposes them and never replays the remaining candidates on resend" do
    calls = 0
    allow(Imports::Applier).to receive(:call).and_wrap_original do |original, **args|
      calls += 1
      raise "simulated failure" if calls == 1
      original.call(**args)
    end
    rows = [csv_row, csv_row(取引番号: "second", 出金金額（円）: "3")]
    result = receive_csv(rows)
    expect(result.processing_errors).to include("processing_failed")
    expect(result.applied_count).to eq(1)
    expect(result.document.import_entries.first.reason_code).to eq("processing_failed")
    expect(receive_csv(rows).applied_count).to eq(0)
    expect(Transaction.count).to eq(1)
  end

  it "detects route changes between ingestion and auto, and invalidates date/review previews" do
    allow(Imports::Applier).to receive(:call).and_return(Imports::Applier::Result.new(status: :held))
    entry = receive_csv.document.import_entries.first
    token = review_token(entry, "distinct")
    date_preview = Imports::BulkDateUpdate.preview(entry_ids: [entry.id], date: "2026-11-01")
    route = @csv_routes["PayPay残高"]
    route.update!(enabled: false)
    route.update!(enabled: true)
    expect(Imports::RuleResolver.automatic_reasons(entry.reload, entry.image_import_draft)).to include("csv_route_changed")
    expect(Imports::ReviewToken.valid?(token, entry: entry, action: "distinct")).to be_falsey
    expect { Imports::BulkDateUpdate.call(token: date_preview.token) }.to raise_error(ArgumentError)
  end

  it "preserves a near-limit identifier through the database and keeps its original ID and digest on resend" do
    base = csv_bytes([csv_row(取引番号: "x")])
    identifier = "0" * (Imports::PaypayCsvParser::MAX_BYTES - base.bytesize - 2)
    rows = [csv_row(取引番号: identifier)]
    result = receive_csv(rows)
    expect(result.processing_errors).to eq([])
    expect(result.applied_count).to eq(1)
    entry = result.document.import_entries.take
    expect(entry.import_identity.external_id == identifier).to be(true)
    expect(entry.payload["csv_raw"]["取引番号"] == identifier).to be(true)
    expect(entry.payload_digest).to eq(Imports::Fingerprint.digest(Imports::Fingerprint.source_payload(entry.payload)))
    expect(receive_csv(rows).applied_count).to eq(0)
    expect(receive_csv(rows, bom: true).document.import_entries.take.state).to eq("reference")
    expect(Imports::CsvSummary.call(document: result.document)[:count]).to eq(1)
    expect(Transaction.count).to eq(1)
  end

  it "adopts an unbound revision and requires explicit special-kind correction without weakening automatic gates" do
    Setting.current.update!(image_import_requires_approval: true)
    first = receive_csv([csv_row(取引内容: "返金")]).document.import_entries.first
    expect(Imports::Applier.call(entry_id: first.id, action: "approve").status).to eq(:held)
    corrected = receive_csv([csv_row(出金金額（円）: "1100")]).document.import_entries.first
    expect(corrected.classification).to eq("correction")
    token = review_token(corrected, "adopt_revision")
    expect(Imports::Applier.call(entry_id: corrected.id, action: "adopt_revision", review_token: token).status).to eq(:applied)
    expect(first.reload.state).to eq("superseded")
    expect(Transaction.count).to eq(1)
    special = receive_csv([csv_row(取引番号: "manual-special", 取引内容: "返金", 出金金額（円）: "22")]).document.import_entries.first
    expect(Imports::Applier.call(entry_id: special.id, action: "approve", attributes: { transaction_kind: "normal" }).status).to eq(:held)
    expect(Imports::Applier.call(entry_id: special.id, action: "approve", attributes: { transaction_kind: "normal" },
      confirmation: { kind_correction: "1", kind_correction_reason: "架空データの確認" }).status).to eq(:applied)
  end

  it "stops after a lost connection prevents recording an automatic failure" do
    allow(Imports::Applier).to receive(:call).and_raise(ActiveRecord::ConnectionFailed)
    allow_any_instance_of(Imports::CsvReceiver).to receive(:record_failure).and_raise(ActiveRecord::ConnectionFailed)
    rows = [csv_row, csv_row(取引番号: "second", 出金金額（円）: "2")]
    result = receive_csv(rows)
    expect(result.processing_errors).to include("connection_lost")
    expect(Imports::Applier).to have_received(:call).once
    expect(Transaction.count).to eq(0)
    expect(result.document.state).to eq("extracted")
  end
end
