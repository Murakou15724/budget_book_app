class UpdateCreditCardClosingDayDefaultToMonthEnd < ActiveRecord::Migration[7.1]
  # Olive(三井住友カード フレキシブルペイ・クレジットモード)の実際の運用に合わせる。
  # 締め日は月末固定のため、closing_dayに31を設定すると
  # (どの月も月内の日にちが31を超えることはないので)常にその月内で締まる、
  # という挙動になる(Transaction#credit_card_payment_due_onの実装に対応)。
  def up
    change_column_default :settings, :credit_card_closing_day, from: 15, to: 31
    execute "UPDATE settings SET credit_card_closing_day = 31 WHERE credit_card_closing_day = 15"
  end

  def down
    change_column_default :settings, :credit_card_closing_day, from: 31, to: 15
    execute "UPDATE settings SET credit_card_closing_day = 15 WHERE credit_card_closing_day = 31"
  end
end
