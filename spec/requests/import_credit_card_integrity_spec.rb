require "rails_helper"

RSpec.describe "imported credit card integrity", type: :request do
  let!(:category) { Category.create!(name: "食費", kind: :expense) }
  let!(:payment_method) { PaymentMethod.create!(import_kind: "credit_card", name: "カード") }
  let!(:account) { Account.create!(name: "カード未払", kind: :credit_pending) }
  let!(:bank) { Account.create!(name: "引落元", kind: :bank) }
  let(:draft) do
    tracked_draft(account: account, category: category, payment_method: payment_method, date: Date.new(2028, 7, 25),
      amount: 1000, credit_card_status: "unpaid")
  end
  let(:entry) { draft.import_entry }

  before do
    Setting.current.update!(credit_card_closing_day: 31, credit_card_payment_day: 26)
    expect(Imports::Applier.call(entry_id: entry.id, action: "approve").status).to eq(:applied)
  end

  it "支払済操作と同じtransactionで対応をconflictにし変更前後を記録する" do
    target = Transaction.find(entry.reload.target_transaction_id)
    patch mark_credit_card_paid_transactions_path, params: { payment_account_id: bank.id, transaction_ids: [target.id] }
    expect(response).to redirect_to(credit_card_unpaids_path)
    expect(target.reload).to be_paid
    expect(target.account_id).to eq(bank.id)
    expect(entry.reload.state).to eq("conflict")
    event = entry.import_events.where(kind: "conflict").last
    expect(event.details.dig("before", "credit_card_status")).to eq("unpaid")
    expect(event.details.dig("after", "credit_card_status")).to eq("paid")
    expect(event.details.dig("after", "account_id")).to eq(bank.id)
    expect(event.details.dig("after", "credit_card_paid_on")).to eq(target.credit_card_paid_on.iso8601)
  end

  it "支払予定日変更と同じtransactionで対応をconflictにしoverrideを記録する" do
    target = Transaction.find(entry.reload.target_transaction_id)
    patch shift_credit_card_payment_due_on_transaction_path(target), params: { direction: "next" }
    expect(response).to redirect_to(credit_card_unpaids_path)
    expect(entry.reload.state).to eq("conflict")
    event = entry.import_events.where(kind: "conflict").last
    expect(event.details.dig("before", "credit_card_payment_due_on_override")).to be_nil
    expect(event.details.dig("after", "credit_card_payment_due_on_override")).to eq(target.reload.credit_card_payment_due_on_override.iso8601)
    expect(target).to be_unpaid
  end
end
