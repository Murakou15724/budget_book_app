require "csv"
require "stringio"

module PaypayCsvFixtures
  def csv_row(**attributes)
    { "取引日" => "2026/10/01 12:34:56", "出金金額（円）" => "1,000", "入金金額（円）" => "-",
      "海外出金金額" => "-", "通貨" => "JPY", "変換レート（円）" => "-", "利用国" => "-",
      "取引内容" => "支払い", "取引先" => "架空店", "取引方法" => "PayPay残高", "支払い区分" => "一回払い",
      "利用者" => "本人", "取引番号" => "000-AbC-123456789012345678901234567890" }.merge(attributes.stringify_keys)
  end

  def csv_bytes(rows = [csv_row], headers: Imports::PaypayCsvParser::HEADERS, row_sep: "\n", bom: false)
    text = CSV.generate(row_sep: row_sep) do |csv|
      csv << headers
      rows.each { |row| csv << headers.map { |key| row[key] } }
    end
    (bom ? "\uFEFF" : "") + text
  end

  def setup_csv_source(automatic: true)
    @bank = Account.create!(name: "銀行-#{SecureRandom.hex(4)}", kind: :bank)
    @wallet = Account.create!(name: "残高-#{SecureRandom.hex(4)}", kind: :e_money)
    @card = Account.create!(name: "カード-#{SecureRandom.hex(4)}", kind: :credit_pending)
    @source = ImportSource.create!(name: "架空PayPay", service_key: "paypay", account: @bank, csv_auto_apply_enabled: automatic)
    @category = Category.create!(name: "架空支出-#{SecureRandom.hex(4)}", kind: :expense)
    @income_category = Category.create!(name: "架空収入-#{SecureRandom.hex(4)}", kind: :income)
    @csv_routes = {}
    { "PayPay残高" => [@wallet, "e_money"], "PayPayクレジット" => [@card, "credit_card"], "架空銀行" => [@bank, "bank"] }.each do |method, (account, kind)|
      payment = PaymentMethod.create!(name: "#{method}-#{SecureRandom.hex(4)}", import_kind: kind)
      route = ImportPaymentRoute.create!(import_source: @source, source_method: method, account: account,
        payment_method: payment, credit_card_status: kind == "credit_card" ? "unpaid" : "not_applicable", enabled: true)
      @csv_routes[method] = route
      confirmed_rule(source: @source, category: @category, payment: payment, merchant: "架空店", channel: "paypay_csv",
        import_payment_route: route, account: account, credit_card_status: route.credit_card_status)
      unless kind == "credit_card"
        confirmed_rule(source: @source, category: @income_category, payment: payment, merchant: "架空勤務先", channel: "paypay_csv",
          import_payment_route: route, account: account)
      end
    end
    Setting.current.update!(image_import_requires_approval: !automatic)
  end

  def receive_csv(rows = [csv_row], **options)
    Imports::CsvReceiver.call(source: @source, file: StringIO.new(csv_bytes(rows, **options)))
  end
end

RSpec.configure { |config| config.include PaypayCsvFixtures }
