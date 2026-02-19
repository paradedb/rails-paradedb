# frozen_string_literal: true
require "date"

module ParadeDB
  module Arel
    class Builder
      INT4_MIN = -2_147_483_648
      INT4_MAX = 2_147_483_647
      RANGE_TYPES = %w[int4range int8range numrange daterange tsrange tstzrange].freeze

      attr_reader :table

      def initialize(table = nil)
        @table = table
      end

      def [](column)
        column_node(column)
      end

      def match(column, *terms, boost: nil)
        rhs = apply_boost(quoted_value(join_terms(terms)), boost)
        infix("&&&", column_node(column), rhs)
      end

      def match_any(column, *terms)
        infix("|||", column_node(column), quoted_value(join_terms(terms)))
      end

      def full_text(column, expression)
        rhs = expression.is_a?(::Arel::Nodes::Node) ? expression : ::Arel.sql(expression.to_s)
        infix("@@@", column_node(column), rhs)
      end

      def phrase(column, text, slop: nil)
        rhs = apply_slop(quoted_value(text), slop)
        infix("###", column_node(column), rhs)
      end

      def fuzzy(column, term, distance: 1, prefix: nil, boost: nil)
        validate_numeric!(distance, :distance)
        rhs = Nodes::FuzzyCast.new(quoted_value(term), quoted_value(distance), prefix: prefix)
        rhs = apply_boost(rhs, boost)
        infix("===", column_node(column), rhs)
      end

      def term(column, term, boost: nil)
        rhs = apply_boost(quoted_value(term), boost)
        infix("===", column_node(column), rhs)
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

      def near(column, left_term, right_term, distance: 1)
        validate_numeric!(distance, :distance)
        # Produce: (left ## distance) ## right
        near_chain = infix("##", infix("##", quoted_value(left_term), quoted_value(distance)), quoted_value(right_term))
        infix("@@@", column_node(column), ::Arel::Nodes::Grouping.new(near_chain))
      end

      def phrase_prefix(column, *terms)
        flat = terms.flatten.compact
        raise ArgumentError, "phrase_prefix requires at least one term" if flat.empty?
        array = Nodes::ArrayLiteral.new(flat.map { |term| quoted_value(term) })
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.phrase_prefix", [array])
        infix("@@@", column_node(column), rhs)
      end

      def parse(column, query, lenient: nil)
        rhs = Nodes::ParseNode.new(quoted_value(query), lenient: lenient)
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

      def agg(json)
        ::Arel::Nodes::NamedFunction.new("pdb.agg", [quoted_value(json)])
      end

      private

      def apply_boost(node, boost)
        return node if boost.nil?
        validate_numeric!(boost, :boost)
        Nodes::BoostCast.new(node, quoted_value(boost))
      end

      def apply_slop(node, slop)
        return node if slop.nil?
        validate_numeric!(slop, :slop)
        Nodes::SlopCast.new(node, quoted_value(slop))
      end

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
            ::Arel::Nodes::SqlLiteral.new(::ActiveRecord::Base.connection.quote_column_name(column.to_s))
          end
        else
          raise ArgumentError, "Unsupported column type: #{column.class}"
        end
      end

      def quoted_value(value)
        ::Arel::Nodes.build_quoted(value)
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
          return values.any? { |v| v < INT4_MIN || v > INT4_MAX } ? "int8range" : "int4range"
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

      def join_terms(terms)
        joined = terms.flatten.compact.map(&:to_s).join(" ")
        raise ArgumentError, "at least one search term is required" if joined.strip.empty?
        joined
      end

      def normalize_term_set_terms(terms)
        values = Array(terms).flatten.compact
        raise ArgumentError, "term_set requires at least one value" if values.empty?

        values
      end

      def validate_numeric!(value, name)
        return if value.nil?
        unless value.is_a?(Numeric)
          raise ArgumentError, "#{name} must be numeric, got #{value.class}"
        end
      end

      def arel_table
        @arel_table ||= table ? ::Arel::Table.new(table.to_s) : nil
      end
    end
  end
end
