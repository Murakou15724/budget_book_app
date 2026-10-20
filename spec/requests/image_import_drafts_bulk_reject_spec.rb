require "rails_helper"

RSpec.describe "image import drafts bulk reject button wording", type: :request do
  it "対応矛盾で却下できない候補を成功件数に含めない" do
    rejected = tracked_draft(amount: 1000)
    conflict = tracked_draft(amount: 2000)
    conflict.import_entry.update!(state: "conflict", reason_code: "target_deleted", target_transaction_id: 999999999)
    delete bulk_reject_image_import_drafts_path, params: { draft_ids: [rejected.id, conflict.id] }
    follow_redirect!
    expect(response.body).to include("1件を却下しました。1件は確認・修正が必要です。")
    expect(conflict.import_entry.reload.state).to eq("conflict")
    expect(rejected.import_entry.reload.state).to eq("rejected")
  end

  it "却下ボタンが「表示中の候補を全件」対象であることを、選択チェックボックスと誤解しないよう明示する" do
    tracked_draft(batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 1000)
    tracked_draft(batch_id: "b1", date: Date.new(2028, 8, 21), direction: :expense, amount: 2000)

    get image_import_drafts_path(batch_id: "b1")

    expect(response.body).to include("表示中の候補をすべて却下")
    expect(response.body).not_to include("選択した候補をまとめて却下")
    expect(response.body).to include('data-turbo-confirm="表示中の候補(2件)をすべて却下しますか？チェックボックスの選択状態は関係なく全件が対象です。"')
  end

  it "カテゴリ選択肢の取得はドラフト件数に関わらず一定回数(支出用・収入用の2回)で済む" do
    Category.create!(name: "食費", kind: :expense, position: 1)
    3.times { |i| tracked_draft(batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 1000 + i) }

    category_queries = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      category_queries += 1 if payload[:sql].match?(/FROM ["`]categories["`]/)
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get image_import_drafts_path(batch_id: "b1")
    end

    expect(category_queries).to eq(2)
  end
end
