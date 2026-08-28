module Gemini
  class ExtractionResult
    attr_reader :items, :error_message

    def self.success(items)
      new(success: true, items: items)
    end

    def self.failure(error_message)
      new(success: false, items: [], error_message: error_message)
    end

    def initialize(success:, items: [], error_message: nil)
      @success = success
      @items = items
      @error_message = error_message
    end

    def success?
      @success
    end
  end
end
