# frozen_string_literal: true

module ParadeDB
  # Query inputs can be nested and reused for search predicates and direct aggregates.
  class SearchQuery
    def initialize(function, values)
      raise ArgumentError, "Unsupported query-input function" unless %w[parse boolean disjunction_max].include?(function)
      @function = function
      @values = values.freeze
      freeze
    end

    def self.parse(query, lenient: false, conjunction_mode: false)
      raise ArgumentError, "query must be a string" unless query.is_a?(String)
      new("parse", [query, lenient, conjunction_mode])
    end

    def self.boolean(must: [], should: [], must_not: [], minimum_should_match: nil)
      unless minimum_should_match.nil? || (minimum_should_match.is_a?(Integer) && minimum_should_match >= 0)
        raise ArgumentError, "minimum_should_match must be a non-negative integer"
      end
      new("boolean", [clauses(must), clauses(should), clauses(must_not), minimum_should_match])
    end

    def self.disjunction_max(disjuncts, tie_breaker: nil)
      values = clauses(disjuncts)
      raise ArgumentError, "disjuncts must not be empty" if values.empty?
      unless tie_breaker.nil? || (tie_breaker.is_a?(Numeric) && tie_breaker.finite? && (0..1).cover?(tie_breaker))
        raise ArgumentError, "tie_breaker must be between 0 and 1"
      end
      new("disjunction_max", [values, tie_breaker])
    end

    def self.clauses(values)
      raise ArgumentError, "clauses must be an array" unless values.is_a?(Array)
      values.map { |value| value.is_a?(SearchQuery) ? value : parse(value) }.freeze
    end
    private_class_method :clauses

    def to_sql(connection: ActiveRecord::Base.connection)
      if @function == "parse"
        args = @values.map { |value| connection.quote(value) }
      else
        arrays = @function == "boolean" ? @values.take(3) : @values.take(1)
        args = arrays.map { |clauses| "ARRAY[#{clauses.map { |q| q.to_sql(connection: connection) }.join(', ')}]::paradedb.searchqueryinput[]" }
        args << connection.quote(@values.last)
      end
      "paradedb.#{@function}(#{args.join(', ')})"
    end
  end
end
