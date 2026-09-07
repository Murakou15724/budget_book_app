# 直近2回の資産スナップショット間で、残高整合性チェック(AccountReconciliation)が
# 検出した差分を「強制的に」解消するためのタスク。
#
# 過去の取引記録が完全でなかった期間の差分まで遡って原因究明するのではなく、
# 「これ以降はチェックが機能する状態」を優先したい場合に使う。
#
# 新しい方(直近)のスナップショットは、現在の実際の残高として信頼し変更しない
# (ダッシュボードの「現在総資産」等はこの値を使うため)。
# 代わりに古い方のスナップショットの値を、見込み増減から逆算した値に書き換える。
namespace :asset_reconciliation do
  desc "直近2回のスナップショット間の差分を、古い方の残高を書き換えて解消する(新しい方は変更しない)"
  task force_align: :environment do
    current, previous = AssetSnapshot.newest_first.first(2)
    abort "資産スナップショットが2件以上登録されている必要があります。" if previous.nil?

    plan = AccountReconciliation.force_align_plan(current, previous)
    if plan.empty?
      puts "#{previous.recorded_on} -> #{current.recorded_on}: 差分はありません。何もしませんでした。"
      next
    end

    puts "#{previous.recorded_on}(古い方)のスナップショットを書き換えます。#{current.recorded_on}(新しい方)は変更しません。"
    # 表示に使ったplanをそのまま適用する(適用直前に再計算すると、表示内容と
    # 実際の書き込み内容がズレうるため)。
    AccountReconciliation.apply_plan!(plan)
    plan.each do |step|
      puts "#{step.account.name}: #{step.old_value}円 -> #{step.new_value}円 " \
           "(見込み増減#{step.expected_delta}円から逆算)"
    end
  end
end
