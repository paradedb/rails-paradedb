# frozen_string_literal: true

require "date"
require_relative "vector"

module ParadeDB
  class QueryBuilder
    RANGE_TYPES = %w[int4range int8range numrange daterange tsrange tstzrange].freeze
    RANGE_RELATIONS = %w[Intersects Contains Within].freeze
    Modifier = Data.define(:type, :value, :options)
    attr_reader :table

    def initialize(table = nil)
      @table = table
    end

    def [](column)
      column_node(column)
    end

    def boost(value, factor)
      validate_numeric!(factor, :factor)
      Modifier.new(type: :boost, value: value, options: { factor: factor })
    end

    def constant(value, score)
      validate_numeric!(score, :score)
      Modifier.new(type: :constant, value: value, options: { score: score })
    end

    def fuzzy(value, distance, prefix: nil, transposition_cost_one: nil)
      validate_fuzzy_distance!(distance)
      Modifier.new(
        type: :fuzzy,
        value: value,
        options: { distance: distance, prefix: prefix, transposition_cost_one: transposition_cost_one }
      )
    end

    def slop(value, distance)
      validate_numeric!(distance, :distance)
      Modifier.new(type: :slop, value: value, options: { distance: distance })
    end

    def tokenize(value, tokenizer)
      raise ArgumentError, "tokenizer must be a Tokenizer" unless tokenizer.is_a?(ParadeDB::Tokenizer)

      Modifier.new(type: :tokenizer, value: value, options: { tokenizer: tokenizer })
    end

    def match(column, term = nil)
      infix("&&&", column_node(column), term_query_node(term))
    end

    def match_any(column, term = nil)
      infix("|||", column_node(column), term_query_node(term))
    end

    def phrase(column, text)
      rhs = text.is_a?(Array) ? array_node(normalize_phrase_terms(text).map { |term| quoted_value(term) }) : search_value_node(text)
      infix("###", column_node(column), rhs)
    end

    def term(column, term)
      infix("===", column_node(column), search_value_node(term))
    end

    def term_set(column, *terms)
      array = array_node(normalize_term_set_terms(terms).map { |term| quoted_value(term) })
      infix("@@@", column_node(column), ::Arel::Nodes::NamedFunction.new("pdb.term_set", [array]))
    end

    def regex(column, pattern)
      infix("@@@", column_node(column), ::Arel::Nodes::NamedFunction.new("pdb.regex", [search_value_node(pattern)]))
    end

    def regex_phrase(column, *patterns, slop: nil, max_expansions: nil)
      args = [array_node(normalize_regex_patterns(patterns).map { |pattern| quoted_value(pattern) })]
      unless slop.nil?
        validate_numeric!(slop, :slop)
        args << keyword_arg_node("slop", slop)
      end
      unless max_expansions.nil?
        validate_integer!(max_expansions, :max_expansions)
        args << keyword_arg_node("max_expansions", max_expansions)
      end
      infix("@@@", column_node(column), ::Arel::Nodes::NamedFunction.new("pdb.regex_phrase", args))
    end

    def near(column, proximity)
      rhs = proximity.is_a?(Modifier) || arel_expression?(proximity) ? search_value_node(proximity) : proximity_query_node(proximity)
      infix("@@@", column_node(column), rhs)
    end

    def phrase_prefix(column, *terms, max_expansion: nil)
      flat = terms.flatten.compact
      raise ArgumentError, "phrase_prefix requires at least one term" if flat.empty?

      args = [array_node(flat.map { |term| quoted_value(term) })]
      unless max_expansion.nil?
        validate_integer!(max_expansion, :max_expansion)
        args << quoted_value(max_expansion)
      end
      infix("@@@", column_node(column), ::Arel::Nodes::NamedFunction.new("pdb.phrase_prefix", args))
    end

    def parse(column, query, lenient: nil, conjunction_mode: nil)
      args = [quoted_value(query)]
      args << keyword_arg_node("lenient", lenient) unless lenient.nil?
      args << keyword_arg_node("conjunction_mode", conjunction_mode) unless conjunction_mode.nil?
      infix("@@@", column_node(column), ::Arel::Nodes::NamedFunction.new("pdb.parse", args))
    end

    def match_all(column)
      infix("@@@", column_node(column), ::Arel::Nodes::NamedFunction.new("pdb.all", []))
    end

    def exists(column)
      infix("@@@", column_node(column), ::Arel::Nodes::NamedFunction.new("pdb.exists", []))
    end

    def range(column, value = nil, gte: nil, gt: nil, lte: nil, lt: nil, type: nil)
      range_node = build_range_node(value, gte: gte, gt: gt, lte: lte, lt: lt, type: type)
      infix("@@@", column_node(column), ::Arel::Nodes::NamedFunction.new("pdb.range", [range_node]))
    end

    def range_term(column, value, relation: nil, range_type: nil)
      infix("@@@", column_node(column), build_range_term_node(value, relation: relation, range_type: range_type))
    end

    def more_like_this(column, key, fields: nil, options: {})
      args = [quoted_value(key)]
      args << array_node(Array(fields).map { |field| quoted_value(field.to_s) }) unless fields.nil?
      options.each { |name, value| args << mlt_option_node(name, value) }
      infix("@@@", column_node(column), ::Arel::Nodes::NamedFunction.new("pdb.more_like_this", args))
    end

    def vector_distance(column, vector, metric: ParadeDB::Vector::DEFAULT_METRIC)
      operator = ParadeDB::Vector::DISTANCE_OPERATORS.fetch(ParadeDB::Vector.normalize_metric(metric))
      infix(operator, column_node(column), vector_operand(vector))
    end

    def score(key)
      ::Arel::Nodes::NamedFunction.new("pdb.score", [column_node(key)])
    end

    def snippet(column, *args)
      ::Arel::Nodes::NamedFunction.new("pdb.snippet", [column_node(column)] + args.map { |arg| quoted_value(arg) })
    end

    def snippets(column, start_tag: nil, end_tag: nil, max_num_chars: nil, limit: nil, offset: nil, sort_by: nil)
      args = [column_node(column)]
      args << keyword_arg_node("start_tag", start_tag) unless start_tag.nil?
      args << keyword_arg_node("end_tag", end_tag) unless end_tag.nil?
      args << keyword_arg_node("max_num_chars", max_num_chars) unless max_num_chars.nil?
      args << keyword_arg_node("limit", limit, quoted_name: true) unless limit.nil?
      args << keyword_arg_node("offset", offset, quoted_name: true) unless offset.nil?
      args << keyword_arg_node("sort_by", sort_by) unless sort_by.nil?
      ::Arel::Nodes::NamedFunction.new("pdb.snippets", args)
    end

    def snippet_positions(column)
      ::Arel::Nodes::NamedFunction.new("pdb.snippet_positions", [column_node(column)])
    end

    def agg(json, exact: nil)
      raise ArgumentError, "exact must be true, false, or nil" unless exact.nil? || exact == true || exact == false

      args = [quoted_value(json)]
      args << quoted_value(false) if exact == false
      ::Arel::Nodes::NamedFunction.new("pdb.agg", args)
    end

    private

    def infix(operator, left, right)
      ::Arel::Nodes::InfixOperation.new(operator, left, right)
    end

    def column_node(column)
      case column
      when ::Arel::Attributes::Attribute, ::Arel::Nodes::Node, ::Arel::Nodes::SqlLiteral
        column
      when Symbol, String
        @table ? arel_table[column.to_sym] : ::Arel.sql(column.to_s)
      else
        raise ArgumentError, "Unsupported column type: #{column.class}"
      end
    end

    def quoted_value(value)
      ::Arel::Nodes.build_quoted(value)
    end

    def array_node(values)
      ::Arel.sql("ARRAY[#{Array.new(values.length, "?").join(", ")}]", *values)
    end

    def cast_node(node, type)
      ::Arel.sql("?::#{type}", node)
    end

    def modifier_node(modifier)
      node = search_value_node(modifier.value)

      case modifier.type
      when :boost
        cast_node(node, "pdb.boost(#{modifier.options[:factor]})")
      when :constant
        node = cast_node(node, "pdb.query") if modifier.value.is_a?(Modifier) && %i[fuzzy slop].include?(modifier.value.type)
        cast_node(node, "pdb.const(#{modifier.options[:score]})")
      when :fuzzy
        args = [modifier.options[:distance]]
        if modifier.options[:transposition_cost_one]
          args << %("#{modifier.options[:prefix] ? 'true' : 'false'}") << '"true"'
        elsif modifier.options[:prefix]
          args << '"true"'
        end
        cast_node(node, "pdb.fuzzy(#{args.join(", ")})")
      when :slop
        cast_node(node, "pdb.slop(#{modifier.options[:distance]})")
      when :tokenizer
        cast_node(node, modifier.options[:tokenizer].render)
      end
    end

    def vector_operand(vector)
      return vector if arel_expression?(vector)

      cast_node(quoted_value(vector.is_a?(String) ? vector : ParadeDB::Vector.literal(vector)), "vector")
    end

    def proximity_query_node(proximity)
      raise ArgumentError, "near requires a ParadeDB.proximity(...) clause" unless proximity.is_a?(ParadeDB::Proximity::Clause)
      raise ArgumentError, "near requires at least one within clause" if proximity.clauses.empty?

      compile_proximity_clause(proximity)
    end

    def compile_proximity_clause(clause)
      current = proximity_operand_node(clause.operand, empty_message: "proximity requires at least one term")
      clause.clauses.each do |within_clause|
        validate_numeric!(within_clause.distance, :distance)
        operator = within_clause.ordered ? "##>" : "##"
        right = proximity_operand_node(within_clause.operand, empty_message: "within requires at least one term")
        current = ::Arel::Nodes::Grouping.new(infix(operator, infix(operator, current, quoted_value(within_clause.distance)), right))
      end
      current
    end

    def prox_regex_node(pattern, max_expansions)
      args = [quoted_value(pattern)]
      unless max_expansions.nil?
        validate_integer!(max_expansions, :max_expansions)
        args << quoted_value(max_expansions)
      end
      ::Arel::Nodes::NamedFunction.new("pdb.prox_regex", args)
    end

    def proximity_operand_node(terms, empty_message:)
      return compile_proximity_clause(terms) if terms.is_a?(ParadeDB::Proximity::Clause)

      values = Array(terms).flatten.compact
      raise ArgumentError, empty_message if values.empty?
      return proximity_term_node(values.first) if values.length == 1

      ::Arel::Nodes::NamedFunction.new("pdb.prox_array", values.map { |term| proximity_term_node(term) })
    end

    def proximity_term_node(term)
      if term.is_a?(ParadeDB::Proximity::Clause)
        raise ArgumentError, "nested proximity clauses must be passed directly, not inside an array"
      end
      return prox_regex_node(term.pattern, term.max_expansions) if term.is_a?(ParadeDB::Proximity::RegexTerm)

      quoted_value(term)
    end

    def build_range_node(value, gte:, gt:, lte:, lt:, type:)
      lower, upper, lower_inclusive, upper_inclusive = normalize_range_bounds(value, gte: gte, gt: gt, lte: lte, lt: lt)
      range_type = normalize_range_type(type || infer_range_type(lower, upper))
      bounds = "#{lower_inclusive ? "[" : "("}#{upper_inclusive ? "]" : ")"}"
      ::Arel::Nodes::NamedFunction.new(range_type, [range_bound_node(lower), range_bound_node(upper), quoted_value(bounds)])
    end

    def normalize_range_bounds(value, gte:, gt:, lte:, lt:)
      if value.is_a?(Range)
        raise ArgumentError, "range bounds cannot be mixed with a Ruby Range value" if [gte, gt, lte, lt].any? { |bound| !bound.nil? }

        return [value.begin, value.end, true, !value.exclude_end?]
      end

      raise ArgumentError, "range expects a Ruby Range or bound options (gte/gt/lte/lt)" unless value.nil?
      raise ArgumentError, "range lower bound cannot include both gte and gt" if !gte.nil? && !gt.nil?
      raise ArgumentError, "range upper bound cannot include both lte and lt" if !lte.nil? && !lt.nil?

      lower = gt.nil? ? gte : gt
      upper = lt.nil? ? lte : lt
      raise ArgumentError, "range requires at least one bound" if lower.nil? && upper.nil?

      [lower, upper, gt.nil?, lt.nil?]
    end

    def infer_range_type(lower, upper)
      values = [lower, upper].compact
      raise ArgumentError, "range requires at least one non-nil bound to infer type" if values.empty?
      return "int8range" if values.all? { |value| value.is_a?(Integer) }
      return "numrange" if values.all? { |value| value.is_a?(Numeric) }
      return "daterange" if values.all? { |value| value.is_a?(Date) && !value.is_a?(DateTime) }
      return "tsrange" if values.all? { |value| value.is_a?(Time) || value.is_a?(DateTime) }

      raise ArgumentError, "Unable to infer range type from bound values; pass type: explicitly"
    end

    def normalize_range_type(range_type)
      value = range_type.to_s
      raise ArgumentError, "Unknown range type: #{range_type.inspect}. Expected one of: #{RANGE_TYPES.join(', ')}" unless RANGE_TYPES.include?(value)

      value
    end

    def normalize_range_relation(relation)
      value = relation.to_s.capitalize
      raise ArgumentError, "Unknown range relation: #{relation.inspect}. Expected one of: #{RANGE_RELATIONS.join(', ')}" unless RANGE_RELATIONS.include?(value)

      value
    end

    def build_range_term_node(value, relation:, range_type:)
      if relation.nil?
        raise ArgumentError, "range_type is only valid when relation is provided" unless range_type.nil?

        return ::Arel::Nodes::NamedFunction.new("pdb.range_term", [quoted_value(value)])
      end

      raise ArgumentError, "relation requires range_type" if range_type.nil?

      cast_value = cast_node(quoted_value(value), normalize_range_type(range_type))
      ::Arel::Nodes::NamedFunction.new("pdb.range_term", [cast_value, quoted_value(normalize_range_relation(relation))])
    end

    def range_bound_node(value)
      value.nil? ? ::Arel.sql("NULL") : quoted_value(value)
    end

    def mlt_option_node(name, value)
      rendered = name.to_sym == :stopwords ? array_node(Array(value).map { |term| quoted_value(term.to_s) }) : quoted_value(value)
      ::Arel::Nodes::InfixOperation.new("=>", ::Arel.sql(name.to_s), rendered)
    end

    def keyword_arg_node(name, value, quoted_name: false)
      ::Arel::Nodes::InfixOperation.new("=>", ::Arel.sql(quoted_name ? %("#{name}") : name), quoted_value(value))
    end

    def term_query_node(term)
      return search_value_node(term) if term.is_a?(Modifier) || arel_expression?(term)

      joined = term.to_s
      raise ArgumentError, "at least one search term is required" if joined.strip.empty?

      quoted_value(joined)
    end

    def search_value_node(value)
      return value if arel_expression?(value)
      return modifier_node(value) if value.is_a?(Modifier)
      return array_node(value.map { |item| quoted_value(item) }) if value.is_a?(Array)
      return proximity_query_node(value) if value.is_a?(ParadeDB::Proximity::Clause)

      quoted_value(value)
    end

    def arel_expression?(value)
      value.is_a?(::Arel::Nodes::Node) || value.is_a?(::Arel::Attributes::Attribute)
    end

    def normalize_term_set_terms(terms)
      values = Array(terms).flatten.compact
      raise ArgumentError, "term_set requires at least one value" if values.empty?

      values
    end

    def normalize_phrase_terms(terms)
      values = Array(terms).flatten.compact.map(&:to_s)
      raise ArgumentError, "phrase array input requires at least one term" if values.empty? || values.all?(&:empty?)

      values
    end

    def normalize_regex_patterns(patterns)
      values = Array(patterns).flatten.compact.map(&:to_s)
      raise ArgumentError, "regex_phrase requires at least one pattern" if values.empty? || values.all?(&:empty?)

      values
    end

    def validate_numeric!(value, name)
      raise ArgumentError, "#{name} must be numeric, got #{value.class}" unless value.is_a?(Numeric)
    end

    def validate_fuzzy_distance!(distance)
      validate_numeric!(distance, :distance)
      raise ArgumentError, "distance must be between 0 and 2" unless (0..2).cover?(distance)
    end

    def validate_integer!(value, name)
      raise ArgumentError, "#{name} must be an integer" unless value.is_a?(Integer)
    end

    def arel_table
      @arel_table ||= ::Arel::Table.new(@table.to_s)
    end
  end
end
