require "net/http"
require "json"
require "base64"

module Gemini
  # PayPay/クレジットカードのスクリーンショットから取引情報を抽出する。
  # 画像データはこの呼び出しの中でのみ使い、どこにも永続化しない。
  class TransactionExtractor
    MODEL = "gemini-3.6-flash".freeze
    ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent".freeze
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60

    RESPONSE_SCHEMA = {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          date: { type: "STRING", description: "取引日(YYYY-MM-DD形式)。読み取れない場合は空文字。" },
          direction: { type: "STRING", enum: %w[expense income] },
          amount: { type: "INTEGER" },
          memo: { type: "STRING", description: "店名や取引内容の簡潔なメモ" },
          category_name: { type: "STRING", description: "候補リストの中から最も近いカテゴリ名。無ければ空文字。" },
          payment_method_name: { type: "STRING", description: "候補リストの中から最も近い支払方法名。無ければ空文字。" },
          account_name: { type: "STRING", description: "候補リストの中から最も近い口座名。無ければ空文字。" }
        },
        required: %w[date direction amount]
      }
    }.freeze

    def initialize(image_bytes:, mime_type:)
      @image_bytes = image_bytes
      @mime_type = mime_type
    end

    def call
      api_key = Rails.application.credentials.dig(:gemini, :api_key)
      return ExtractionResult.failure("Gemini APIキーが設定されていません。") if api_key.blank?

      parse_response(request_gemini(api_key))
    rescue Net::OpenTimeout, Net::ReadTimeout
      ExtractionResult.failure("Gemini APIへの接続がタイムアウトしました。時間をおいて再試行してください。")
    rescue StandardError => e
      Rails.logger.error("Gemini::TransactionExtractor failed: #{e.class}: #{e.message}")
      ExtractionResult.failure("画像の解析に失敗しました。")
    end

    private

    def request_gemini(api_key)
      uri = URI("#{ENDPOINT}?key=#{api_key}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = build_request_body.to_json

      http.request(request)
    end

    def build_request_body
      {
        contents: [
          {
            parts: [
              { text: prompt },
              { inline_data: { mime_type: @mime_type, data: Base64.strict_encode64(@image_bytes) } }
            ]
          }
        ],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: RESPONSE_SCHEMA
        }
      }
    end

    def prompt
      <<~PROMPT
        あなたは家計簿アプリの入力補助AIです。添付された画像(PayPayの支払い完了画面、またはクレジットカードの利用履歴一覧のスクリーンショット)から、取引情報をすべて抽出してください。

        画像に複数件の取引が含まれる場合は、そのすべてを配列として抽出してください。

        各取引について、以下のカテゴリ・支払方法・口座の候補リストの中から、内容に最も近いものを1つ選んで返してください。適切な候補が無い場合は空文字を返してください(候補にないものを推測で作らないでください)。

        支出カテゴリ候補: #{Category.expense.order(:position, :name).pluck(:name).join(", ")}
        収入カテゴリ候補: #{Category.income.order(:position, :name).pluck(:name).join(", ")}
        支払方法候補: #{PaymentMethod.order(:position, :name).pluck(:name).join(", ")}
        口座候補: #{Account.order(:position, :name).pluck(:name).join(", ")}

        日付が画像から読み取れない場合は空文字にしてください。金額は手数料等を含まない実際の支払い・入金額の整数にしてください。
      PROMPT
    end

    def parse_response(response)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("Gemini API error: #{response.code} #{response.body}")
        return ExtractionResult.failure("Gemini APIの呼び出しに失敗しました(#{response.code})。")
      end

      body = JSON.parse(response.body)
      text = body.dig("candidates", 0, "content", "parts", 0, "text")
      return ExtractionResult.failure("Gemini APIから予期しない形式の応答が返されました。") if text.blank?

      items = JSON.parse(text)
      return ExtractionResult.failure("Gemini APIから予期しない形式の応答が返されました。") unless items.is_a?(Array)

      ExtractionResult.success(items)
    rescue JSON::ParserError => e
      Rails.logger.error("Gemini response parse error: #{e.message}")
      ExtractionResult.failure("Gemini APIの応答の解析に失敗しました。")
    end
  end
end
