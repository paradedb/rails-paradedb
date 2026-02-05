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

      # Binary operators
      def match(column, *terms, boost: nil)
        right = join_terms(terms)
        build_predicate(Nodes::Match, column, right, boost: boost)
      end

      def match_any(column, *terms)
        right = join_terms(terms)
        Nodes::MatchAny.new(column_node(column), value_node(right))
      end

      def full_text(column, expression)
        rhs =
          case expression
          when Nodes::Node
            expression
          else
            Nodes::SqlLiteral.new(expression)
          end
        Nodes::FullText.new(column_node(column), rhs)
      end

      def phrase(column, text, slop: nil)
        rhs = value_node(text)
        rhs = Nodes::Slop.new(rhs, slop) if slop
        Nodes::Phrase.new(column_node(column), rhs)
      end

      def fuzzy(column, term, distance: 1, prefix: nil, boost: nil)
        Nodes::Fuzzy.new(column_node(column), value_node(term), distance: distance, prefix: prefix, boost: boost)
      end

      def term(column, term, boost: nil)
        build_predicate(Nodes::Term, column, term, boost: boost)
      end

      def regex(column, pattern)
        Nodes::Regex.new(column_node(column), value_node(pattern))
      end

      def near(column, left_term, right_term, distance: 1)
        Nodes::Near.new(column_node(column), terms: [left_term, right_term], distance: distance)
      end

      def phrase_prefix(column, *terms)
        Nodes::PhrasePrefix.new(column_node(column), terms.flatten)
      end

      def more_like_this(column, key, fields: nil)
        Nodes::MoreLikeThis.new(column_node(column), value_node(key), fields: fields&.map { |f| value_node(f) })
      end

      # Functions
      def score(key)
        Nodes::Score.new("score", column_node(key))
      end

      def snippet(column, *args)
        Nodes::Snippet.new("snippet", column_node(column), *args)
      end

      def agg(json)
        Nodes::Agg.new("agg", json)
      end

      private

      def build_predicate(klass, column, value, boost: nil)
        rhs = value_node(value)
        rhs = Nodes::Boost.new(rhs, boost) if boost
        klass.new(column_node(column), rhs)
      end

      def column_node(column)
        case column
        when Nodes::Attribute then column
        else
          Nodes::Attribute.new(column, table: table)
        end
      end

      def value_node(val)
        val.is_a?(Nodes::Node) ? val : Nodes::Value.new(val)
      end

      def join_terms(terms)
        terms.flatten.compact.map(&:to_s).join(" ")
      end
    end
  end
end
