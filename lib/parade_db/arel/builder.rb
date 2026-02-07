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
        rhs = quoted_value(join_terms(terms))
        rhs = Nodes::BoostCast.new(rhs, quoted_value(boost)) unless boost.nil?
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
        rhs = quoted_value(text)
        rhs = Nodes::SlopCast.new(rhs, quoted_value(slop)) unless slop.nil?
        infix("###", column_node(column), rhs)
      end

      def fuzzy(column, term, distance: 1, prefix: nil, boost: nil)
        rhs = Nodes::FuzzyCast.new(quoted_value(term), quoted_value(distance), prefix: prefix)
        rhs = Nodes::BoostCast.new(rhs, quoted_value(boost)) unless boost.nil?
        infix("===", column_node(column), rhs)
      end

      def term(column, term, boost: nil)
        rhs = quoted_value(term)
        rhs = Nodes::BoostCast.new(rhs, quoted_value(boost)) unless boost.nil?
        infix("===", column_node(column), rhs)
      end

      def regex(column, pattern)
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.regex", [quoted_value(pattern)])
        infix("@@@", column_node(column), rhs)
      end

      def near(column, left_term, right_term, distance: 1)
        near_chain = infix("##", infix("##", quoted_value(left_term), quoted_value(distance)), quoted_value(right_term))
        infix("@@@", column_node(column), ::Arel::Nodes::Grouping.new(near_chain))
      end

      def phrase_prefix(column, *terms)
        array = Nodes::ArrayLiteral.new(terms.flatten.compact.map { |term| quoted_value(term) })
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

      def more_like_this(column, key, fields: nil)
        args = [quoted_value(key)]
        unless fields.nil?
          field_values = fields.map { |field| quoted_value(field) }
          args << Nodes::ArrayLiteral.new(field_values)
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

      def infix(operator, left, right)
        ::Arel::Nodes::InfixOperation.new(operator, left, right)
      end

      def column_node(column)
        case column
        when ::Arel::Attributes::Attribute, ::Arel::Nodes::Node
          column
        else
          if arel_table
            arel_table[column.to_sym]
          else
            ::Arel::Nodes::SqlLiteral.new(::ActiveRecord::Base.connection.quote_column_name(column.to_s))
          end
        end
      end

      def quoted_value(value)
        ::Arel::Nodes.build_quoted(value)
      end

      def join_terms(terms)
        terms.flatten.compact.map(&:to_s).join(" ")
      end

      def arel_table
        @arel_table ||= table ? ::Arel::Table.new(table.to_s) : nil
      end
    end
  end
end
