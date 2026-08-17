module LegacyImport
  # 旧Excel家計簿「取引入力」「資産管理」「月次振り返り」シートの実データを投入する。
  # 日付はExcelのシリアル値をそのまま書き起こし、インポート時にRubyのDateへ変換する。
  #
  # 「取引入力」シートの1件(Excelシリアル日付46201, 交通費, 金額0円, 支払方法・口座が空欄)は、
  # メモに「クレカとして換算しよう」とある通り原本でも未確定の書きかけデータであり、
  # 本アプリの必須項目・金額>0のバリデーションを満たさないため移行対象から除外する
  # (下記TRANSACTIONS内、同日付・同カテゴリの野球観戦の直後にコメントで記録)。
  module TransactionalData
    EXCEL_EPOCH = Date.new(1899, 12, 30)

    TRANSACTIONS = [
      { date: 46199, entry_type: "実績", direction: "支出", category: "その他", amount: 93_848, payment_method: "クレカ", account: "クレカ仮置き", satisfaction: 5, regret: "いいえ", credit_card_status: "支払済" },
      { date: 46194, entry_type: "実績", direction: "支出", category: "外食", amount: 11_271, payment_method: "PayPay", account: "PayPay", memo: "ボウリングなど含む", satisfaction: 4, regret: "いいえ", credit_card_status: "対象外" },
      { date: 46194, entry_type: "実績", direction: "収入", category: "その他収入", amount: 2_000, payment_method: "PayPay", account: "PayPay", satisfaction: 3, regret: "いいえ", credit_card_status: "対象外" },
      { date: 46197, entry_type: "実績", direction: "収入", category: "臨時収入", amount: 10_000, payment_method: "PayPay", account: "PayPay", memo: "誕生日（京都より）", satisfaction: 5, regret: "いいえ", credit_card_status: "対象外" },
      { date: 46198, entry_type: "実績", direction: "収入", category: "給与", amount: 285_301, payment_method: "銀行振込", account: "三井住友", memo: "ライブリッツ", satisfaction: 5, regret: "いいえ", credit_card_status: "対象外" },
      { date: 46200, entry_type: "実績", direction: "支出", category: "外食", amount: 2_695, payment_method: "PayPay", account: "PayPay", memo: "鷹觜と横浜", satisfaction: 5, regret: "いいえ", credit_card_status: "対象外" },
      { date: 46201, entry_type: "実績", direction: "支出", category: "野球観戦", amount: 2_480, payment_method: "PayPay", account: "PayPay", satisfaction: 4, regret: "いいえ", credit_card_status: "対象外" },
      # 46201 交通費 0円(支払方法・口座欄が空)は書きかけデータのため除外
      { date: 46202, entry_type: "実績", direction: "支出", category: "日用品", amount: 3_326, payment_method: "PayPay", account: "PayPay", memo: "プロテイン", satisfaction: 4, regret: "いいえ", credit_card_status: "対象外" },
      { date: 46203, entry_type: "実績", direction: "収入", category: "ボーナス", amount: 119_396, payment_method: "銀行振込", account: "三井住友", memo: "初ボーナス！", satisfaction: 4, regret: "いいえ", credit_card_status: "対象外" },
      { date: 46229, entry_type: "予定", direction: "支出", category: "その他", amount: 83_065, payment_method: "クレカ", account: "クレカ仮置き", satisfaction: 5, regret: "いいえ", credit_card_status: "未払" },
      { date: 46208, entry_type: "実績", direction: "支出", category: "外食", amount: 4_000, payment_method: "PayPay", account: "PayPay", memo: "櫂との浦安ドライブ（2000円痛い）", satisfaction: 4, regret: "はい", credit_card_status: "対象外" },
      { date: 46215, entry_type: "実績", direction: "支出", category: "家電・大きな買い物", amount: 29_162, payment_method: "PayPay", account: "PayPay", memo: "イヤホンとモニター", satisfaction: 5, regret: "いいえ", credit_card_status: "対象外" }
    ].freeze

    ASSET_SNAPSHOTS = [
      { date: 46189, balances: { "ゆうちょ" => 170, "三井住友" => 229_367, "三菱UFJ" => 0, "PayPay" => 1_041, "PayPay証券" => 150_000, "SBI証券" => 180_000, "現金" => 20_000 }, memo: "入力開始日" },
      { date: 46196, balances: { "ゆうちょ" => 170, "三井住友" => 209_367, "三菱UFJ" => 0, "PayPay" => 6_470, "PayPay証券" => 150_000, "SBI証券" => 180_000, "現金" => 20_000 } },
      { date: 46198, balances: { "ゆうちょ" => 170, "三井住友" => 494_668, "三菱UFJ" => 0, "PayPay" => 16_470, "PayPay証券" => 150_000, "SBI証券" => 180_000, "現金" => 20_000 } },
      { date: 46199, balances: { "ゆうちょ" => 170, "三井住友" => 383_940, "三菱UFJ" => 0, "PayPay" => 16_470, "PayPay証券" => 150_000, "SBI証券" => 180_000, "現金" => 20_000 } },
      { date: 46203, balances: { "ゆうちょ" => 170, "三井住友" => 503_336, "三菱UFJ" => 0, "PayPay" => 11_251, "PayPay証券" => 150_000, "SBI証券" => 180_000, "現金" => 20_000 } },
      { date: 46213, balances: { "ゆうちょ" => 170, "三井住友" => 503_336, "三菱UFJ" => 0, "PayPay" => 8_131, "PayPay証券" => 150_000, "SBI証券" => 210_000, "現金" => 25_000 } },
      { date: 46217, balances: { "ゆうちょ" => 170, "三井住友" => 473_336, "三菱UFJ" => 0, "PayPay" => 8_969, "PayPay証券" => 150_000, "SBI証券" => 210_000, "現金" => 25_000 } },
      { date: 46224, balances: { "ゆうちょ" => 170, "三井住友" => 470_336, "三菱UFJ" => 0, "PayPay" => 179, "PayPay証券" => 150_000, "SBI証券" => 210_000, "現金" => 22_000 } },
      { date: 46224, balances: { "ゆうちょ" => 2_050, "三井住友" => 740_963, "三菱UFJ" => 0, "PayPay" => 11_966, "PayPay証券" => 150_000, "SBI証券" => 210_000, "現金" => 20_000 }, memo: "100万円達成！！" },
      { date: 46241, balances: { "ゆうちょ" => 0, "三井住友" => 592_663, "三菱UFJ" => 0, "PayPay" => 11_929, "PayPay証券" => 180_000, "SBI証券" => 210_000, "現金" => 20_000 } }
    ].freeze

    MONTHLY_REVIEWS = [
      {
        year: 2026, month: 6, satisfaction: 5, regret_note: "なし", good_spending_note: "特になし？",
        next_month_cut_note: "特になし", comment: "この管理はどこまで続くか…笑（ボーナスうれしい！）"
      }
    ].freeze

    def self.excel_date(serial)
      EXCEL_EPOCH + serial
    end

    ENTRY_TYPES = { "実績" => :actual, "予定" => :planned }.freeze
    DIRECTIONS = { "支出" => :expense, "収入" => :income }.freeze
    CREDIT_CARD_STATUSES = { "対象外" => :not_applicable, "未払" => :unpaid, "支払済" => :paid }.freeze

    def self.import!
      ActiveRecord::Base.transaction do
        import_transactions!
        import_asset_snapshots!
        import_monthly_reviews!
      end
    end

    def self.import_transactions!
      TRANSACTIONS.each do |attrs|
        direction = DIRECTIONS.fetch(attrs[:direction])
        Transaction.create!(
          date: excel_date(attrs[:date]),
          entry_type: ENTRY_TYPES.fetch(attrs[:entry_type]),
          direction: direction,
          # Categoryはname一意ではなくname+kindで一意なため、収支区分から求まるkindで絞り込む。
          category: Category.find_by!(name: attrs[:category], kind: direction),
          amount: attrs[:amount],
          payment_method: PaymentMethod.find_by!(name: attrs[:payment_method]),
          account: Account.find_by!(name: attrs[:account]),
          memo: attrs[:memo],
          satisfaction: attrs[:satisfaction],
          regret: attrs[:regret] == "はい",
          credit_card_status: CREDIT_CARD_STATUSES.fetch(attrs[:credit_card_status])
        )
      end
      puts "取引を#{TRANSACTIONS.size}件投入しました。"
    end

    def self.import_asset_snapshots!
      ASSET_SNAPSHOTS.each do |attrs|
        snapshot = AssetSnapshot.create!(recorded_on: excel_date(attrs[:date]), memo: attrs[:memo])
        attrs[:balances].each do |account_name, balance|
          snapshot.asset_balances.create!(account: Account.find_by!(name: account_name), balance: balance)
        end
      end
      puts "資産スナップショットを#{ASSET_SNAPSHOTS.size}件投入しました。"
    end

    def self.import_monthly_reviews!
      MONTHLY_REVIEWS.each { |attrs| MonthlyReview.create!(attrs) }
      puts "月次振り返りを#{MONTHLY_REVIEWS.size}件投入しました。"
    end
  end
end
