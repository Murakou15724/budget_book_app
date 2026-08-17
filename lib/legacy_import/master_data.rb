module LegacyImport
  # 旧Excel家計簿「予算・設定」シートのマスタデータを投入する。
  # 月別予算上書き表は全カテゴリ・全月とも基本月予算と同額だったため、
  # CategoryMonthlyBudgetの上書きレコードは作成しない(アプリの仕様上、
  # 基本月予算と同額の月は「上書きなし」として扱われるため)。
  module MasterData
    EXPENSE_CATEGORIES = [
      { name: "食費", monthly_budget: 0 },
      { name: "外食", monthly_budget: 23_000 },
      { name: "カフェ・コンビニ", monthly_budget: 3_000 },
      { name: "交通費", monthly_budget: 2_000 },
      { name: "日用品", monthly_budget: 0 },
      { name: "家賃", monthly_budget: 0 },
      { name: "水道光熱費", monthly_budget: 0 },
      { name: "通信費", monthly_budget: 8_000 },
      { name: "サブスク", monthly_budget: 4_000, note: "Youtube GPT クラウド" },
      { name: "服・美容", monthly_budget: 5_000 },
      { name: "医療", monthly_budget: 0 },
      { name: "交際費", monthly_budget: 0 },
      { name: "趣味", monthly_budget: 10_000 },
      { name: "野球観戦", monthly_budget: 10_000, note: "趣味とは独立" },
      { name: "旅行", monthly_budget: 0, note: "積立的に予算化しても可" },
      { name: "書籍・学習", monthly_budget: 0 },
      { name: "ゲーム・アプリ", monthly_budget: 0 },
      { name: "家電・大きな買い物", monthly_budget: 0 },
      { name: "税金・保険", monthly_budget: 0 },
      { name: "その他", monthly_budget: 10_000 },
      { name: "固定NISA", monthly_budget: 50_000 }
    ].freeze

    INCOME_CATEGORIES = [
      { name: "給与", note: "変動可" },
      { name: "ボーナス", note: "変動可" },
      { name: "交通費精算", note: "変動可" },
      { name: "臨時収入" },
      { name: "その他収入" }
    ].freeze

    ACCOUNTS = [
      { name: "ゆうちょ", kind: :bank },
      { name: "三井住友", kind: :bank },
      { name: "三菱UFJ", kind: :bank },
      { name: "PayPay", kind: :e_money },
      { name: "PayPay証券", kind: :securities },
      { name: "SBI証券", kind: :securities },
      { name: "現金", kind: :cash },
      { name: "クレカ仮置き", kind: :credit_pending }
    ].freeze

    PAYMENT_METHODS = [
      { name: "現金" },
      { name: "口座引落" },
      { name: "PayPay" },
      { name: "クレカ", note: "支払日までは仮置き" },
      { name: "銀行振込" },
      { name: "証券入金" },
      { name: "その他" }
    ].freeze

    SETTINGS = { target_year: 2026, total_savings_goal: 1_000_000, monthly_savings_goal: 50_000 }.freeze

    def self.import!
      EXPENSE_CATEGORIES.each_with_index do |attrs, index|
        Category.find_or_create_by!(kind: :expense, name: attrs[:name]) do |c|
          c.monthly_budget = attrs[:monthly_budget]
          c.note = attrs[:note]
          c.position = index
        end
      end

      INCOME_CATEGORIES.each_with_index do |attrs, index|
        Category.find_or_create_by!(kind: :income, name: attrs[:name]) do |c|
          c.note = attrs[:note]
          c.position = index
        end
      end

      ACCOUNTS.each_with_index do |attrs, index|
        Account.find_or_create_by!(name: attrs[:name]) do |a|
          a.kind = attrs[:kind]
          a.position = index
        end
      end

      PAYMENT_METHODS.each_with_index do |attrs, index|
        PaymentMethod.find_or_create_by!(name: attrs[:name]) do |p|
          p.note = attrs[:note]
          p.position = index
        end
      end

      Setting.current.update!(SETTINGS)

      puts "マスタデータを投入しました: 支出カテゴリ#{EXPENSE_CATEGORIES.size}件 / 収入カテゴリ#{INCOME_CATEGORIES.size}件 / " \
           "口座#{ACCOUNTS.size}件 / 支払方法#{PAYMENT_METHODS.size}件 / 設定値"
    end
  end
end
