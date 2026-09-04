# 「8月分支払い」「8月分の合計」のような、クレジットカード等の月次引落・精算額を
# そのまま支出として登録してしまっている取引(=個別の利用明細と二重計上している
# 可能性がある取引)を洗い出すための調査タスク。
#
# 自動での一括変換は行わない。個別明細(未払→支払済)がすでに登録済みで
# 実際に二重計上になっている場合のみ、convert_to_transfer で振替に変換すること。
namespace :duplicate_expense_audit do
  MEMO_KEYWORDS = %w[月分支払い 月分の合計 月分合計 引落 引き落とし 精算 まとめ].freeze

  desc "クレカ引落等の合算値が支出として登録されている疑いのある取引を一覧表示する"
  task list: :environment do
    # 開発環境(MySQL)・本番環境(PostgreSQL)の両方で動くよう、REGEXPではなくLIKEのORで検索する。
    condition = MEMO_KEYWORDS.map { "memo LIKE ?" }.join(" OR ")
    values = MEMO_KEYWORDS.map { |keyword| "%#{keyword}%" }
    candidates = Transaction.expense.where(condition, *values).order(:date)

    if candidates.none?
      puts "メモに #{MEMO_KEYWORDS.join('/')} を含む支出取引は見つかりませんでした。"
      next
    end

    puts "以下の支出取引は、クレカ引落等の合算値の可能性があります。"
    puts "同時期に個別の利用明細(クレカ仮置き口座への未払い→支払済の取引)が別途登録されていないか確認してください。"
    puts "重複していると判断した場合は、次のタスクで振替(transfer)に変換できます:"
    puts "  bin/rails duplicate_expense_audit:convert_to_transfer ID=<id>[,<id>...]"
    puts "-" * 60

    candidates.each do |t|
      puts "ID=#{t.id} #{t.date} #{t.amount}円 [#{t.category&.name}] #{t.account.name} memo=#{t.memo}"
    end
  end

  desc "指定したID(カンマ区切り)の支出取引を振替(transfer)に変換する。カテゴリはクリアされる"
  task convert_to_transfer: :environment do
    ids = ENV["ID"].to_s.split(",").map(&:strip).reject(&:blank?)
    abort "変換対象を ID=1,2,3 のように指定してください" if ids.empty?

    Transaction.where(id: ids).find_each do |t|
      unless t.expense?
        puts "ID=#{t.id} は支出ではないためスキップしました(direction=#{t.direction})。"
        next
      end

      t.update!(direction: :transfer, category_id: nil, credit_card_status: :not_applicable)
      puts "ID=#{t.id} (#{t.date} #{t.amount}円 memo=#{t.memo}) を振替に変換しました。"
    end
  end
end
