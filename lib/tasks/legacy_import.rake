# 旧Excel家計簿「MONEY QUEST」(docs/家計簿_2026.xlsx, 2026年分)からのデータ移行タスク。
# 要件定義書(docs/要件定義書.md)8章の移行方針に基づき、Excelから読み取った値を
# そのままRubyのデータとして書き起こしている(xlsxを都度パースする専用gemは
# 一度きりの移行のために追加しない)。
namespace :legacy_import do
  desc "旧Excel家計簿のマスタデータ(カテゴリ・口座・支払方法・設定値)を投入する"
  task master_data: :environment do
    LegacyImport::MasterData.import!
  end

  desc "旧Excel家計簿の取引・資産スナップショット・月次振り返りを投入する"
  task transactional_data: :environment do
    # 取引・資産スナップショットには一意制約がなく、再実行すると重複投入されるため、
    # 既存データがある場合は明示的にFORCE=1を付けない限り中断する。
    if !ENV["FORCE"] && (Transaction.exists? || AssetSnapshot.exists? || MonthlyReview.exists?)
      abort "取引または資産スナップショットが既に存在するため中断しました。再実行する場合は FORCE=1 を付けてください。"
    end

    LegacyImport::TransactionalData.import!
  end

  desc "旧Excel家計簿のデータを全て投入する(マスタ→取引等の順)"
  task all: [:master_data, :transactional_data]
end
