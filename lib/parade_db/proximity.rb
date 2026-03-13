# frozen_string_literal: true

module ParadeDB
  module Proximity
    class RegexTerm
      attr_reader :pattern, :max_expansions

      def initialize(pattern, max_expansions: nil)
        raise ArgumentError, "pattern must be a String, got #{pattern.class}" unless pattern.is_a?(String)
        unless max_expansions.nil? || max_expansions.is_a?(Integer)
          raise ArgumentError, "max_expansions must be an integer"
        end

        @pattern = pattern
        @max_expansions = max_expansions
      end
    end
  end
end
