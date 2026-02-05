# frozen_string_literal: true

module ParadeDB
  module Arel
    class Visitor
      def initialize(connection = nil)
        @connection = connection
      end

      def accept(node)
        case node
        when Nodes::Match
          "#{visit(node.left)} &&& #{quote(node.right)}"
        when Nodes::MatchAny
          "#{visit(node.left)} ||| #{quote(node.right)}"
        when Nodes::Phrase
          "#{visit(node.left)} ### #{quote(node.right)}"
        when Nodes::Term
          "#{visit(node.left)} === #{quote(node.right)}"
        when Nodes::Fuzzy
          rhs = "#{quote(node.right)}::pdb.fuzzy(#{node.distance}"
          rhs += %Q(, "true") if !node.prefix.nil? && node.prefix
          rhs += ")"
          rhs += "::pdb.boost(#{node.boost})" if node.boost
          "#{visit(node.left)} === #{rhs}"
        when Nodes::FullText
          "#{visit(node.left)} @@@ #{quote(node.right)}"
        when Nodes::Regex
          "#{visit(node.left)} @@@ pdb.regex(#{quote(node.right)})"
        when Nodes::Near
          left_term, right_term = node.right
          proximity = "(#{quote(left_term)} ## #{node.distance} ## #{quote(right_term)})"
          "#{visit(node.left)} @@@ #{proximity}"
        when Nodes::PhrasePrefix
          terms = Array(node.right).map { |t| quote(t) }.join(", ")
          "#{visit(node.left)} @@@ pdb.phrase_prefix(ARRAY[#{terms}])"
        when Nodes::MoreLikeThis
          fields_sql = node.fields ? ", ARRAY[#{Array(node.fields).map { |f| quote(f) }.join(", ")}]" : ""
          "#{visit(node.left)} @@@ pdb.more_like_this(#{quote(node.right)}#{fields_sql})"
        when Nodes::Boost
          "#{visit(node.expr)}::pdb.boost(#{quote(node.factor)})"
        when Nodes::Slop
          "#{visit(node.expr)}::pdb.slop(#{quote(node.distance)})"
        when Nodes::Score
          "pdb.score(#{visit_args(node.args)})"
        when Nodes::Snippet
          "pdb.snippet(#{visit_args(node.args)})"
        when Nodes::Agg
          "pdb.agg(#{visit_args(node.args)})"
        when Nodes::And
          "(#{accept(node.left)} AND #{accept(node.right)})"
        when Nodes::Or
          "(#{accept(node.left)} OR #{accept(node.right)})"
        when Nodes::Not
          "NOT (#{accept(node.expr)})"
        when Nodes::Attribute
          visit_attribute(node)
        when Nodes::SqlLiteral
          node.value.to_s
        when Nodes::Value
          quote(node.value)
        else
          raise ArgumentError, "Unsupported node: #{node.inspect}"
        end
      end

      private

      def visit(node)
        accept(node)
      end

      def visit_attribute(node)
        if node.table
          %{#{quote_identifier(node.table)}.#{quote_identifier(node.name)}}
        else
          quote_identifier(node.name)
        end
      end

      def visit_args(args)
        args.map { |a| accept_valueish(a) }.join(", ")
      end

      def accept_valueish(val)
        case val
        when Nodes::Node
          accept(val)
        else
          quote(val)
        end
      end

      def quote_identifier(name)
        %("#{name}")
      end

      def quote(val)
        return accept(val) if val.is_a?(Nodes::Node)
        connection.quote(val)
      end

      def connection
        @connection || ActiveRecord::Base.connection
      end
    end
  end
end
