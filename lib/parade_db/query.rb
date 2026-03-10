# frozen_string_literal: true

module ParadeDB
  # Helpers for building ParadeDB query JSON payloads in Ruby.
  module Query
    module_function

    def regex(pattern)
      raise ArgumentError, "pattern must be a String, got #{pattern.class}" unless pattern.is_a?(String)

      { "regex" => { "pattern" => pattern } }
    end
  end
end
