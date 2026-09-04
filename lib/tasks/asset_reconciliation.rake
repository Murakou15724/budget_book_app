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
    current, previous = AssetSnapshot.order(recorded_on: :desc, id: :desc).first(2)
    abort "資産スナップショットが2件以上登録されている必要があります。" if previous.nil?

    mismatches = AccountReconciliation.build_for(current, previous)
    if mismatches.empty?
      puts "#{previous.recorded_on} -> #{current.recorded_on}: 差分はありません。何もしませんでした。"
      next
    end

    puts "#{previous.recorded_on}(古い方)のスナップショットを書き換えます。#{current.recorded_on}(新しい方)は変更しません。"
    mismatches.each do |mismatch|
      current_balance = current.asset_balances.find_by(account: mismatch.account).balance
      previous_balance_record = previous.asset_balances.find_by(account: mismatch.account)
      old_value = previous_balance_record.balance
      new_value = current_balance - mismatch.expected_delta

      previous_balance_record.update!(balance: new_value)
      puts "#{mismatch.account.name}: #{old_value}円 -> #{new_value}円 " \
           "(#{current.recorded_on}時点の残高#{current_balance}円と、見込み増減#{mismatch.expected_delta}円から逆算)"
    end
  end
end
