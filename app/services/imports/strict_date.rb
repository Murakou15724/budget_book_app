module Imports
  module StrictDate
    module_function

    def parse(value)
      return valid(value) if value.is_a?(Date)
      return unless value.is_a?(String)

      match = /\A(\d{4})-(\d{2})-(\d{2})\z/.match(value)
      valid(Date.new(*match.captures.map(&:to_i))) if match
    rescue Date::Error
      nil
    end

    def source(payload)
      return unless payload["date_year_explicit"] == true && !Array(payload["uncertain_fields"]).include?("date")

      raw = payload["raw_date"]
      return unless raw.is_a?(String)

      match = /\A(\d{4})(?:-(\d{1,2})-(\d{1,2})|\/(\d{1,2})\/(\d{1,2})|年(\d{1,2})月(\d{1,2})日)\z/.match(raw)
      return unless match

      parts = match.captures.compact.map(&:to_i)
      date = valid(Date.new(*parts))
      date if date && date == parse(payload["date"])
    rescue Date::Error
      nil
    end

    def valid(date)
      date if date > Date.new(1900, 1, 1) && date < Date.new(2100, 1, 1)
    end
  end
end
