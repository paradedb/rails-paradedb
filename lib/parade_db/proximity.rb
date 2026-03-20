# frozen_string_literal: true

module ParadeDB
  module Proximity
    module Chainable
      def within(distance, *terms, ordered: false)
        Clause.new(self).within(distance, *terms, ordered: ordered)
      end
    end

    class RegexTerm
      include Chainable

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

    class Within
      attr_reader :distance, :operand, :ordered

      def initialize(distance, operand, ordered: false)
        @distance = distance
        @operand = operand
        @ordered = ordered
      end
    end

    class Clause
      include Chainable

      attr_reader :operand, :clauses

      def initialize(*terms, operand: nil, clauses: [])
        @operand = operand || self.class.normalize_operand(terms)
        @clauses = clauses
      end

      def within(distance, *terms, ordered: false)
        normalized_operand =
          begin
            self.class.normalize_operand(terms)
          rescue ArgumentError => e
            raise unless e.message == "proximity requires at least one term"

            raise ArgumentError, "within requires at least one term"
          end

        self.class.new(
          operand: operand,
          clauses: clauses + [Within.new(distance, normalized_operand, ordered: ordered)]
        )
      end

      def self.normalize_operand(terms)
        values = Array(terms).flatten(1).compact
        raise ArgumentError, "proximity requires at least one term" if values.empty?

        values.length == 1 ? values.first : values
      end
    end
  end
end
