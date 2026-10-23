module Imports
  module TransactionKindClassifier
    KINDS = %w[normal charge transfer card_settlement refund cancellation fee unknown].freeze
    SPECIAL_WORDS = {
      "card_settlement" => /カード引落|カード引き落|クレジット.*引落/,
      "refund" => /返金/, "cancellation" => /取消|キャンセル/,
      "charge" => /チャージ/, "transfer" => /振替|口座間移動/, "fee" => /手数料/
    }.freeze
    module_function

    def call(payload:)
      text = [payload["memo"], payload["merchant"], *payload.fetch("evidence", {}).to_h.values].join(" ")
      special = SPECIAL_WORDS.find { |_, pattern| pattern.match?(text) }&.first
      special || (KINDS.include?(payload["transaction_kind"]) ? payload["transaction_kind"] : "unknown")
    end
  end
end
