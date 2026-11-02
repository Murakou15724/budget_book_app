require "csv"
require "date"

module Imports
  class PaypayCsvParser
    MAX_BYTES = 8 * 1024 * 1024
    MAX_ROWS = 1_000
    HEADERS = %w[取引日 出金金額（円） 入金金額（円） 海外出金金額 通貨 変換レート（円） 利用国 取引内容 取引先 取引方法 支払い区分 利用者 取引番号].freeze
    EMPTY_AMOUNTS = ["", "-", "ー", "0"].freeze
    Parsed = Struct.new(:rows, :header, keyword_init: true)
    Row = Struct.new(:raw, :payload, :draft_attributes, :errors, :holds, :external_id, keyword_init: true)
    class FileError < StandardError
      attr_reader :code, :row_number, :physical_line

      def initialize(code:, row_number: nil, physical_line: nil)
        @code, @row_number, @physical_line = code, row_number, physical_line
        super(code)
      end
    end

    def self.call(bytes:)
      new.call(bytes)
    end

    def call(bytes)
      fail_file("csv_too_large") if bytes.bytesize > MAX_BYTES
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      fail_file("csv_encoding") unless text.valid_encoding?
      fail_file("csv_nul") if text.include?("\0")
      text.delete_prefix!("\uFEFF")
      fail_file("csv_empty") if text.empty?
      @logical_line = 1
      parser = CSV.new(text, converters: nil, skip_blanks: false)
      header = parser.shift
      fail_file("csv_headers") unless header && header.size == HEADERS.size && header.sort == HEADERS.sort
      @header_read = true
      physical_line = parser.line.count("\n")

      rows = []
      while (cells = parser.shift)
        @logical_line += 1
        physical_line += parser.line.count("\n") + (parser.line.end_with?("\n") ? 0 : 1)
        fail_file("csv_columns", physical_line: physical_line) unless cells.size == HEADERS.size
        fail_file("csv_too_many_rows", physical_line: physical_line) if rows.size >= MAX_ROWS
        rows << build_row(header.zip(cells.map { |cell| cell || "" }).to_h, physical_line)
      end
      Parsed.new(rows: rows, header: header)
    rescue CSV::MalformedCSVError
      @logical_line += 1 if @header_read
      fail_file("csv_syntax")
    end

    private

    def fail_file(code, physical_line: nil)
      raise FileError.new(code: code, row_number: @logical_line, physical_line: physical_line)
    end

    def strip_ascii(value)
      value.gsub(/\A[ \t\r\n\f\v]+|[ \t\r\n\f\v]+\z/, "")
    end

    def amount(value)
      value = strip_ascii(value)
      return "0" if EMPTY_AMOUNTS.include?(value)
      return unless /\A(?:[1-9][0-9]*|[1-9][0-9]{0,2}(?:,[0-9]{3})+)\z/.match?(value)

      value.delete(",")
    end

    def timestamp(value)
      value = strip_ascii(value)
      return unless /\A20[0-9]{2}\/[0-9]{2}\/[0-9]{2} [0-9]{2}:[0-9]{2}(?::[0-9]{2})?\z/.match?(value)

      format = value.size == 16 ? "%Y/%m/%d %H:%M" : "%Y/%m/%d %H:%M:%S"
      time = DateTime.strptime(value + " +0900", format + " %z")
      time if time.strftime(format) == value
    rescue Date::Error, ArgumentError
      nil
    end

    def build_row(raw, physical_line)
      errors, holds = [], []
      time = timestamp(raw.fetch("取引日"))
      errors << "csv_date" unless time
      outgoing, incoming = %w[出金金額（円） 入金金額（円）].map { |key| amount(raw.fetch(key)) }
      errors << "csv_amount" unless outgoing && incoming
      positives = [outgoing, incoming].map { |value| value && value != "0" }
      direction = positives == [true, false] ? "expense" : (positives == [false, true] ? "income" : nil)
      errors << "csv_amount_direction" unless direction
      normalized = direction == "expense" ? outgoing : (direction == "income" ? incoming : nil)
      integer = normalized && Integer(normalized, 10)
      draft_amount = integer if integer&.between?(1, 2**31 - 1)
      errors << "csv_amount_range" if integer && !draft_amount

      external_id = raw.fetch("取引番号")
      if external_id.blank? || external_id.match?(/[[:cntrl:]]/)
        errors << "csv_external_id"
        external_id = nil
      end
      content, method, merchant = raw.values_at("取引内容", "取引方法", "取引先")
      errors << "csv_required" if [content, method, merchant].any?(&:blank?)
      holds << "csv_merchant_length" if merchant.length > 255
      holds << "csv_foreign" if !["", "JPY"].include?(raw.fetch("通貨")) ||
        %w[海外出金金額 変換レート（円） 利用国].any? { |key| !EMPTY_AMOUNTS.include?(strip_ascii(raw.fetch(key))) }
      holds << "csv_points" if [content, method].any? { |value| value.include?("ポイント") } || external_id&.start_with?("lp-")
      holds << "csv_mixed_method" if ImportPaymentRoute.mixed_method?(method)
      holds << "csv_payment_type" unless ["", "-", "ー", "一回払い", "1回払い"].include?(raw.fetch("支払い区分"))
      holds << "csv_user" unless ["", "本人"].include?(raw.fetch("利用者"))

      evidence = { "amount" => normalized.to_s.first(255), "direction" => direction.to_s,
        "transaction_kind" => content.first(255), "merchant" => merchant.first(255) }
      kind = TransactionKindClassifier.call(payload: { "memo" => content, "merchant" => merchant, "evidence" => evidence })
      special = case content
      when /送金|譲渡|受け取|受取|銀行口座.*出金/ then "transfer"
      when /引落|引き落|精算/ then "card_settlement"
      end
      kind = special if special && kind == "unknown"
      normal = (strip_ascii(content) == "支払い" && direction == "expense") || (strip_ascii(content) == "給与" && direction == "income")
      if kind == "unknown" && normal && (holds & %w[csv_foreign csv_points csv_mixed_method]).empty?
        kind = "normal"
      end
      errors << "csv_content_direction" if (strip_ascii(content) == "支払い" && direction == "income") ||
        (strip_ascii(content) == "給与" && direction == "expense")
      holds << "csv_special" unless kind == "normal"
      uncertain = []
      uncertain << "date" unless time
      uncertain << "amount" unless draft_amount
      uncertain << "direction" unless direction
      uncertain << "merchant" if merchant.blank? || merchant.length > 255
      uncertain << "transaction_kind" unless kind == "normal"
      payload = { "csv_raw" => raw, "csv_parser_version" => "paypay-csv-v1", "csv_row_number" => @logical_line,
        "csv_physical_line" => physical_line, "csv_errors" => errors.uniq, "csv_holds" => holds.uniq,
        "csv_amounts" => { "outgoing" => outgoing, "incoming" => incoming }, "date" => time&.to_date&.iso8601,
        "occurred_at" => time&.iso8601, "amount" => draft_amount || normalized, "direction" => direction,
        "currency" => holds.include?("csv_foreign") ? raw.fetch("通貨") : "JPY", "source_status" => content,
        "source_method" => method, "merchant" => merchant, "memo" => content.first(255), "transaction_kind" => kind,
        "raw_date" => raw.fetch("取引日"), "date_year_explicit" => !!time, "uncertain_fields" => uncertain, "evidence" => evidence }
      metadata = { "version" => 1, "source_kind" => kind, "evidence" => evidence, "uncertain_fields" => uncertain }
      metadata["csv_preview"] = { "occurred_at" => time&.iso8601, "merchant" => merchant.first(255),
        "source_method" => method.first(255), "external_id" => external_id&.first(255),
        "reasons" => errors.uniq + holds.uniq }
      Row.new(raw: raw, payload: payload, errors: errors.uniq, holds: holds.uniq, external_id: external_id,
        draft_attributes: { date: time&.to_date, date_origin: time ? "source" : "unresolved", direction: direction,
          amount: draft_amount, memo: content.first(255), transaction_kind: kind, confirmation_metadata: metadata, rule_decision: {} })
    end
  end
end
