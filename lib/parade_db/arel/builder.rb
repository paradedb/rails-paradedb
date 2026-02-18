# frozen_string_literal: true

module ParadeDB
  module Arel
    class Builder
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

      def join_terms(terms)
        joined = terms.flatten.compact.map(&:to_s).join(" ")
        raise ArgumentError, "at least one search term is required" if joined.strip.empty?
        joined
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
