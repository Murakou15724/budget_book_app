module Imports
  module MerchantKey
    module_function

    def normalize(value)
      return unless value.is_a?(String) && value.valid_encoding?

      key = value.unicode_normalize(:nfkc).gsub(/[[:space:]]+/, " ").strip.downcase
      key if key.present? && key.length <= 255
    end
  end
end
