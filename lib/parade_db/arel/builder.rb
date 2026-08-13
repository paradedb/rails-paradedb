# frozen_string_literal: true
require "date"
require_relative "../vector"

module ParadeDB
  module Arel
    class Builder
      RANGE_TYPES = %w[int4range int8range numrange daterange tsrange tstzrange].freeze
      RANGE_RELATIONS = %w[Intersects Contains Within].freeze
      attr_reader :table

      def initialize(table = nil)
        @table = table
      end

      def [](column)
        column_node(column)
      end

      def boost(value, factor)
        validate_numeric!(factor, :factor)
        Nodes::BoostCast.new(search_value_node(value), quoted_value(factor))
      end

      def constant(value, score)
        validate_numeric!(score, :score)
        node = search_value_node(value)
        node = Nodes::QueryCast.new(node) if node.is_a?(Nodes::FuzzyCast) || node.is_a?(Nodes::SlopCast)
        Nodes::ConstCast.new(node, quoted_value(score))
      end

      def fuzzy(value, distance, prefix: nil, transposition_cost_one: nil)
        validate_fuzzy_distance!(distance)
        Nodes::FuzzyCast.new(
          search_value_node(value),
          quoted_value(distance),
          prefix: prefix,
          transposition_cost_one: transposition_cost_one
        )
      end

      def slop(value, distance)
        validate_numeric!(distance, :distance)
        Nodes::SlopCast.new(search_value_node(value), quoted_value(distance))
      end

      def tokenize(value, tokenizer)
        raise ArgumentError, "tokenizer must be a Tokenizer" unless tokenizer.is_a?(ParadeDB::Tokenizer)

        Nodes::TokenizerCast.new(search_value_node(value), tokenizer.render())
      end

      def match(column, term = nil)
        infix("&&&", column_node(column), term_query_node(term))
      end

      def match_any(column, term = nil)
        infix("|||", column_node(column), term_query_node(term))
      end

      def full_text(column, expression)
        rhs = expression.is_a?(::Arel::Nodes::Node) ? expression : ::Arel.sql(expression.to_s)
        infix("@@@", column_node(column), rhs)
      end

      def phrase(column, text)
        rhs =
          if text.is_a?(::Array)
            Nodes::ArrayLiteral.new(normalize_phrase_terms(text).map { |term| quoted_value(term) })
          elsif arel_expression?(text)
            text
          else
            quoted_value(text)
          end
        infix("###", column_node(column), rhs)
      end

      def term(column, term)
        infix("===", column_node(column), arel_expression?(term) ? term : quoted_value(term))
      end

      def term_set(column, *terms)
        normalized_terms = normalize_term_set_terms(terms)
        array = Nodes::ArrayLiteral.new(normalized_terms.map { |term| quoted_value(term) })
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.term_set", [array])
        infix("@@@", column_node(column), rhs)
      end

      def regex(column, pattern)
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.regex", [quoted_value(pattern)])
        infix("@@@", column_node(column), rhs)
      end

      def regex_phrase(column, *patterns, slop: nil, max_expansions: nil)
        normalized_patterns = normalize_regex_patterns(patterns)
        args = [Nodes::ArrayLiteral.new(normalized_patterns.map { |pattern| quoted_value(pattern) })]
        unless slop.nil?
          validate_numeric!(slop, :slop)
          args << keyword_arg_node("slop", slop)
        end
        unless max_expansions.nil?
          validate_integer!(max_expansions, :max_expansions)
          args << keyword_arg_node("max_expansions", max_expansions)
        end
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.regex_phrase", args)
        infix("@@@", column_node(column), rhs)
      end

      def near(column, proximity)
        rhs = arel_expression?(proximity) ? proximity : proximity_query_node(proximity)
        infix("@@@", column_node(column), rhs)
      end

      def phrase_prefix(column, *terms, max_expansion: nil)
        flat = terms.flatten.compact
        raise ArgumentError, "phrase_prefix requires at least one term" if flat.empty?
        array = Nodes::ArrayLiteral.new(flat.map { |term| quoted_value(term) })
        args = [array]
        unless max_expansion.nil?
          validate_integer!(max_expansion, :max_expansion)
          args << quoted_value(max_expansion)
        end
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.phrase_prefix", args)
        infix("@@@", column_node(column), rhs)
      end

      def parse(column, query, lenient: nil, conjunction_mode: nil)
        rhs = Nodes::ParseNode.new(
          quoted_value(query),
          lenient: lenient,
          conjunction_mode: conjunction_mode
        )
        infix("@@@", column_node(column), rhs)
      end

      def match_all(column)
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.all", [])
        infix("@@@", column_node(column), rhs)
      end

      def exists(column)
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.exists", [])
        infix("@@@", column_node(column), rhs)
      end

      def range(column, value = nil, gte: nil, gt: nil, lte: nil, lt: nil, type: nil)
        range_node = build_range_node(value, gte: gte, gt: gt, lte: lte, lt: lt, type: type)
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.range", [range_node])
        infix("@@@", column_node(column), rhs)
      end

      def range_term(column, value, relation: nil, range_type: nil)
        rhs = build_range_term_node(value, relation: relation, range_type: range_type)
        infix("@@@", column_node(column), rhs)
      end

      def more_like_this(column, key, fields: nil, options: {})
        args = [quoted_value(key)]
        unless fields.nil?
          field_values = Array(fields).map { |field| quoted_value(field.to_s) }
          args << Nodes::ArrayLiteral.new(field_values)
        end

        options.each do |name, value|
          args << mlt_option_node(name, value)
        end

        rhs = ::Arel::Nodes::NamedFunction.new("pdb.more_like_this", args)
        infix("@@@", column_node(column), rhs)
      end

      def l2_distance(column, vector)
        vector_distance(column, vector, metric: :l2)
      end

      def cosine_distance(column, vector)
        vector_distance(column, vector, metric: :cosine)
      end

      def inner_product(column, vector)
        vector_distance(column, vector, metric: :ip)
      end

      def vector_distance(column, vector, metric: ParadeDB::Vector::DEFAULT_METRIC)
        operator = ParadeDB::Vector::DISTANCE_OPERATORS.fetch(ParadeDB::Vector.normalize_metric(metric))
        infix(operator, column_node(column), vector_operand(vector))
      end

      def score(key)
        ::Arel::Nodes::NamedFunction.new("pdb.score", [column_node(key)])
      end

      def snippet(column, *args)
        call_args = [column_node(column)] + args.map { |arg| quoted_value(arg) }
        ::Arel::Nodes::NamedFunction.new("pdb.snippet", call_args)
      end

      def snippets(
        column,
        start_tag: nil,
        end_tag: nil,
        max_num_chars: nil,
        limit: nil,
        offset: nil,
        sort_by: nil
      )
        call_args = [column_node(column)]
        call_args << keyword_arg_node("start_tag", start_tag) unless start_tag.nil?
        call_args << keyword_arg_node("end_tag", end_tag) unless end_tag.nil?
        call_args << keyword_arg_node("max_num_chars", max_num_chars) unless max_num_chars.nil?
        call_args << keyword_arg_node("limit", limit, quoted_name: true) unless limit.nil?
        call_args << keyword_arg_node("offset", offset, quoted_name: true) unless offset.nil?
        call_args << keyword_arg_node("sort_by", sort_by) unless sort_by.nil?
        ::Arel::Nodes::NamedFunction.new("pdb.snippets", call_args)
      end

      def snippet_positions(column)
        ::Arel::Nodes::NamedFunction.new("pdb.snippet_positions", [column_node(column)])
      end

      def agg(json, exact: nil)
        unless exact.nil? || exact == true || exact == false
          raise ArgumentError, "exact must be true, false, or nil"
        end

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
          if arel_table
            arel_table[column.to_sym]
          else
            ::Arel.sql(column.to_s)
          end
        else
          raise ArgumentError, "Unsupported column type: #{column.class}"
        end
      end

      def quoted_value(value)
        ::Arel::Nodes.build_quoted(value)
      end

      def vector_operand(vector)
        return vector if arel_expression?(vector)

        literal = vector.is_a?(String) ? vector : ParadeDB::Vector.literal(vector)
        Nodes::TypeCast.new(quoted_value(literal), "vector")
      end

      def proximity_query_node(proximity)
        unless proximity.is_a?(ParadeDB::Proximity::Clause)
          raise ArgumentError, "near requires a ParadeDB.proximity(...) clause"
        end

        if proximity.clauses.empty?
          raise ArgumentError, "near requires at least one within clause"
        end

        compile_proximity_clause(proximity)
      end

      def compile_proximity_clause(clause)
        current = proximity_operand_node(clause.operand, empty_message: "proximity requires at least one term")

        clause.clauses.each do |within_clause|
          validate_numeric!(within_clause.distance, :distance)
          operator = within_clause.ordered ? "##>" : "##"
          right_operand = proximity_operand_node(within_clause.operand, empty_message: "within requires at least one term")
          current = ::Arel::Nodes::Grouping.new(
            infix(operator, infix(operator, current, quoted_value(within_clause.distance)), right_operand)
          )
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

      def prox_array_node(terms, empty_message:)
        values = terms.map { |term| proximity_term_node(term) }
        raise ArgumentError, empty_message if values.empty?

        ::Arel::Nodes::NamedFunction.new("pdb.prox_array", values)
      end

      def proximity_operand_node(terms, empty_message:)
        return compile_proximity_clause(terms) if terms.is_a?(ParadeDB::Proximity::Clause)

        normalized_terms = normalize_proximity_terms(terms)
        raise ArgumentError, empty_message if normalized_terms.empty?

        if normalized_terms.length == 1
          proximity_term_node(normalized_terms.first)
        else
          prox_array_node(normalized_terms, empty_message: empty_message)
        end
      end

      def proximity_term_node(term)
        if term.is_a?(ParadeDB::Proximity::Clause)
          raise ArgumentError, "nested proximity clauses must be passed directly, not inside an array"
        elsif term.is_a?(ParadeDB::Proximity::RegexTerm)
          prox_regex_node(term.pattern, term.max_expansions)
        else
          quoted_value(term)
        end
      end

      def build_range_node(value, gte:, gt:, lte:, lt:, type:)
        lower, upper, lower_inclusive, upper_inclusive = normalize_range_bounds(value, gte: gte, gt: gt, lte: lte, lt: lt)
        normalized_type = normalize_range_type(type || infer_range_type(lower, upper))
        bounds = "#{lower_inclusive ? "[" : "("}#{upper_inclusive ? "]" : ")"}"

        ::Arel::Nodes::NamedFunction.new(
          normalized_type,
          [range_bound_node(lower), range_bound_node(upper), quoted_value(bounds)]
        )
      end

      def normalize_range_bounds(value, gte:, gt:, lte:, lt:)
        if value.is_a?(::Range)
          if [gte, gt, lte, lt].any? { |bound| !bound.nil? }
            raise ArgumentError, "range bounds cannot be mixed with a Ruby Range value"
          end

          return [value.begin, value.end, true, !value.exclude_end?]
        end

        unless value.nil?
          raise ArgumentError, "range expects a Ruby Range or bound options (gte/gt/lte/lt)"
        end

        if !gte.nil? && !gt.nil?
          raise ArgumentError, "range lower bound cannot include both gte and gt"
        end

        if !lte.nil? && !lt.nil?
          raise ArgumentError, "range upper bound cannot include both lte and lt"
        end

        lower = gt.nil? ? gte : gt
        upper = lt.nil? ? lte : lt
        lower_inclusive = gt.nil?
        upper_inclusive = lt.nil?

        if lower.nil? && upper.nil?
          raise ArgumentError, "range requires at least one bound"
        end

        [lower, upper, lower_inclusive, upper_inclusive]
      end

      def infer_range_type(lower, upper)
        values = [lower, upper].compact
        raise ArgumentError, "range requires at least one non-nil bound to infer type" if values.empty?

        if values.all? { |v| v.is_a?(::Integer) }
          return "int8range"
        end

        if values.all? { |v| v.is_a?(::Numeric) }
          return "numrange"
        end

        if values.all? { |v| v.is_a?(::Date) && !v.is_a?(::DateTime) }
          return "daterange"
        end

        if values.all? { |v| v.is_a?(::Time) || v.is_a?(::DateTime) }
          return "tsrange"
        end

        raise ArgumentError, "Unable to infer range type from bound values; pass type: explicitly"
      end

      def normalize_range_type(range_type)
        value = range_type.to_s
        unless RANGE_TYPES.include?(value)
          raise ArgumentError, "Unknown range type: #{range_type.inspect}. Expected one of: #{RANGE_TYPES.join(', ')}"
        end
        value
      end

      def normalize_range_relation(relation)
        value = relation.to_s.capitalize
        unless RANGE_RELATIONS.include?(value)
          raise ArgumentError, "Unknown range relation: #{relation.inspect}. Expected one of: #{RANGE_RELATIONS.join(', ')}"
        end
        value
      end

      def build_range_term_node(value, relation:, range_type:)
        if relation.nil?
          raise ArgumentError, "range_type is only valid when relation is provided" unless range_type.nil?

          return ::Arel::Nodes::NamedFunction.new("pdb.range_term", [quoted_value(value)])
        end

        raise ArgumentError, "relation requires range_type" if range_type.nil?

        normalized_relation = normalize_range_relation(relation)
        normalized_type = normalize_range_type(range_type)
        cast_value = Nodes::TypeCast.new(quoted_value(value), normalized_type)

        ::Arel::Nodes::NamedFunction.new("pdb.range_term", [cast_value, quoted_value(normalized_relation)])
      end

      def range_bound_node(value)
        return ::Arel.sql("NULL") if value.nil?

        quoted_value(value)
      end

      def mlt_option_node(name, value)
        key = ::Arel::Nodes::SqlLiteral.new(name.to_s)
        rendered_value =
          if name.to_sym == :stopwords
            stopwords = Array(value).map { |term| quoted_value(term.to_s) }
            Nodes::ArrayLiteral.new(stopwords)
          else
            quoted_value(value)
          end

        ::Arel::Nodes::InfixOperation.new("=>", key, rendered_value)
      end

      def keyword_arg_node(name, value, quoted_name: false)
        key = quoted_name ? %("#{name}") : name
        ::Arel::Nodes::InfixOperation.new(
          "=>",
          ::Arel::Nodes::SqlLiteral.new(key),
          quoted_value(value)
        )
      end

      def join_term(term)
        joined = term.to_s
        raise ArgumentError, "at least one search term is required" if joined.strip.empty?
        joined
      end

      def term_query_node(term)
        return term if arel_expression?(term)

        quoted_value(join_term(term))
      end

      def search_value_node(value)
        return value if arel_expression?(value)
        return Nodes::ArrayLiteral.new(value.map { |item| quoted_value(item) }) if value.is_a?(::Array)
        return proximity_query_node(value) if value.is_a?(ParadeDB::Proximity::Clause)

        quoted_value(value)
      end

      def arel_expression?(value)
        value.is_a?(::Arel::Nodes::Node) ||
          value.is_a?(::Arel::Attributes::Attribute) ||
          value.is_a?(::Arel::Nodes::SqlLiteral)
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

      def normalize_proximity_terms(terms)
        Array(terms).flatten.compact
      end

      def validate_numeric!(value, name)
        unless value.is_a?(Numeric)
          raise ArgumentError, "#{name} must be numeric, got #{value.class}"
        end
      end

      def validate_fuzzy_distance!(distance)
        validate_numeric!(distance, :distance)
        unless (0..2).cover?(distance)
          raise ArgumentError, "distance must be between 0 and 2"
        end
      end

      def validate_integer!(value, name)
        unless value.is_a?(Integer)
          raise ArgumentError, "#{name} must be an integer"
        end
      end

      def arel_table
        @arel_table ||= table ? ::Arel::Table.new(table.to_s) : nil
      end
    end
  end
end
