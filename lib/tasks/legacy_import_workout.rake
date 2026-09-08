# 旧Excel筋トレ管理(筋トレ管理_2026.xlsx)からのデータ移行タスク。
# 要件定義書(docs/筋トレ記録_要件定義書.md)6章の移行方針に基づき、Excelから読み取った値を
# そのままRubyのデータとして書き起こしている(xlsxを都度パースする専用gemは
# 一度きりの移行のために追加しない)。find_or_create_by!ベースなので再実行しても安全。
namespace :legacy_import do
  desc "旧Excel筋トレ管理のデータ(種目マスタ・日次記録)を投入する"
  task workout_data: :environment do
    LegacyImport::WorkoutData.import!
  end
end
