require "rails_helper"

RSpec.describe "image import drafts bulk reject button wording", type: :request do
  it "却下ボタンが「表示中の候補を全件」対象であることを、選択チェックボックスと誤解しないよう明示する" do
    ImageImportDraft.create!(batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 1000)
    ImageImportDraft.create!(batch_id: "b1", date: Date.new(2028, 8, 21), direction: :expense, amount: 2000)

    get image_import_drafts_path(batch_id: "b1")

    expect(response.body).to include("表示中の候補をすべて却下")
    expect(response.body).not_to include("選択した候補をまとめて却下")
    expect(response.body).to include('data-turbo-confirm="表示中の候補(2件)をすべて却下しますか？チェックボックスの選択状態は関係なく全件が対象です。"')
  end

  it "カテゴリ選択肢の取得はドラフト件数に関わらず一定回数(支出用・収入用の2回)で済む" do
    Category.create!(name: "食費", kind: :expense, position: 1)
    3.times { |i| ImageImportDraft.create!(batch_id: "b1", date: Date.new(2028, 8, 20), direction: :expense, amount: 1000 + i) }

    category_queries = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      category_queries += 1 if payload[:sql].include?("`categories`")
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get image_import_drafts_path(batch_id: "b1")
    end

    expect(category_queries).to eq(2)
  end
end
