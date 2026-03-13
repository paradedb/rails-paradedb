# frozen_string_literal: true
require_relative "../tokenizer_sql"

module ParadeDB
  module Arel
    module Predications
      TOKENIZER_EXPRESSION = /\A[a-zA-Z_][a-zA-Z0-9_]*(?:(?:::|\.)[a-zA-Z_][a-zA-Z0-9_]*)*(?:\(\s*[a-zA-Z0-9_'".,=\s:-]*\s*\))?\z/.freeze
      BUILDER = Builder.new.freeze

      def pdb_match(*terms, tokenizer: nil, distance: nil, prefix: nil, transposition_cost_one: nil, boost: nil)
        rhs = pdb_quoted(pdb_join_terms(terms))
        rhs = pdb_apply_fuzzy(rhs, distance: distance, prefix: prefix, transposition_cost_one: transposition_cost_one)
        rhs = pdb_apply_tokenizer(rhs, tokenizer)
        rhs = pdb_apply_boost(rhs, boost)
        ::Arel::Nodes::InfixOperation.new("&&&", self, rhs)
      end

      def pdb_match_any(*terms, tokenizer: nil, distance: nil, prefix: nil, transposition_cost_one: nil, boost: nil)
        rhs = pdb_quoted(pdb_join_terms(terms))
        rhs = pdb_apply_fuzzy(rhs, distance: distance, prefix: prefix, transposition_cost_one: transposition_cost_one)
        rhs = pdb_apply_tokenizer(rhs, tokenizer)
        rhs = pdb_apply_boost(rhs, boost)
        ::Arel::Nodes::InfixOperation.new("|||", self, rhs)
      end

      def pdb_full_text(expression)
        rhs = expression.is_a?(::Arel::Nodes::Node) ? expression : ::Arel.sql(expression.to_s)
        ::Arel::Nodes::InfixOperation.new("@@@", self, rhs)
      end

      def pdb_phrase(text, slop: nil, tokenizer: nil)
        BUILDER.phrase(self, text, slop: slop, tokenizer: tokenizer)
      end

      def pdb_term(term, distance: nil, prefix: nil, transposition_cost_one: nil, boost: nil)
        rhs = pdb_quoted(term)
        rhs = pdb_apply_fuzzy(rhs, distance: distance, prefix: prefix, transposition_cost_one: transposition_cost_one)
        rhs = pdb_apply_boost(rhs, boost)
        ::Arel::Nodes::InfixOperation.new("===", self, rhs)
      end

      def pdb_term_set(*terms)
        BUILDER.term_set(self, *terms)
      end

      def pdb_regex(pattern)
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.regex", [pdb_quoted(pattern)])
        ::Arel::Nodes::InfixOperation.new("@@@", self, rhs)
      end

      def pdb_regex_phrase(*patterns, slop: nil, max_expansions: nil)
        BUILDER.regex_phrase(self, *patterns, slop: slop, max_expansions: max_expansions)
      end

      def pdb_near(*terms, anchor:, distance:, ordered: false)
        BUILDER.near(self, *terms, anchor: anchor, distance: distance, ordered: ordered)
      end

      def pdb_phrase_prefix(*terms, max_expansion: nil)
        flat = terms.flatten.compact
        raise ArgumentError, "phrase_prefix requires at least one term" if flat.empty?

        array = Nodes::ArrayLiteral.new(flat.map { |term| pdb_quoted(term) })
        args = [array]
        unless max_expansion.nil?
          pdb_validate_integer!(max_expansion, :max_expansion)
          args << pdb_quoted(max_expansion)
        end
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.phrase_prefix", args)
        ::Arel::Nodes::InfixOperation.new("@@@", self, rhs)
      end

      def pdb_parse(query, lenient: nil, conjunction_mode: nil)
        rhs = Nodes::ParseNode.new(
          pdb_quoted(query),
          lenient: lenient,
          conjunction_mode: conjunction_mode
        )
        ::Arel::Nodes::InfixOperation.new("@@@", self, rhs)
      end

      def pdb_all
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.all", [])
        ::Arel::Nodes::InfixOperation.new("@@@", self, rhs)
      end

      def pdb_exists
        rhs = ::Arel::Nodes::NamedFunction.new("pdb.exists", [])
        ::Arel::Nodes::InfixOperation.new("@@@", self, rhs)
      end

      def pdb_range(value = nil, gte: nil, gt: nil, lte: nil, lt: nil, type: nil)
        BUILDER.range(self, value, gte: gte, gt: gt, lte: lte, lt: lt, type: type)
      end

      def pdb_range_term(value, relation: nil, range_type: nil)
        BUILDER.range_term(self, value, relation: relation, range_type: range_type)
      end

      def pdb_more_like_this(key, fields: nil, options: {})
        args = [pdb_quoted(key)]

        unless fields.nil?
          field_values = Array(fields).map { |field| pdb_quoted(field.to_s) }
          args << Nodes::ArrayLiteral.new(field_values)
        end

        options.each do |name, value|
          key_node = ::Arel::Nodes::SqlLiteral.new(name.to_s)
          rendered_value =
            if value.is_a?(Array)
              Nodes::ArrayLiteral.new(Array(value).map { |term| pdb_quoted(term.to_s) })
            else
              pdb_quoted(value)
            end
          args << ::Arel::Nodes::InfixOperation.new("=>", key_node, rendered_value)
        end

        rhs = ::Arel::Nodes::NamedFunction.new("pdb.more_like_this", args)
        ::Arel::Nodes::InfixOperation.new("@@@", self, rhs)
      end

      def pdb_score
        ::Arel::Nodes::NamedFunction.new("pdb.score", [self])
      end

      def pdb_snippet(*args)
        ::Arel::Nodes::NamedFunction.new("pdb.snippet", [self] + args.map { |arg| pdb_quoted(arg) })
      end

      def pdb_snippets(
        start_tag: nil,
        end_tag: nil,
        max_num_chars: nil,
        limit: nil,
        offset: nil,
        sort_by: nil
      )
        BUILDER.snippets(
          self,
          start_tag: start_tag,
          end_tag: end_tag,
          max_num_chars: max_num_chars,
          limit: limit,
          offset: offset,
          sort_by: sort_by
        )
      end

      def pdb_snippet_positions
        ::Arel::Nodes::NamedFunction.new("pdb.snippet_positions", [self])
      end

      private

      def pdb_apply_boost(node, boost)
        return node if boost.nil?

        pdb_validate_numeric!(boost, :boost)
        Nodes::BoostCast.new(node, pdb_quoted(boost))
      end

      def pdb_apply_fuzzy(node, distance:, prefix:, transposition_cost_one:)
        fuzzy_enabled = !distance.nil? || prefix || transposition_cost_one
        return node unless fuzzy_enabled

        normalized_distance = distance.nil? ? 1 : distance
        pdb_validate_numeric!(normalized_distance, :distance)
        unless (0..2).cover?(normalized_distance)
          raise ArgumentError, "distance must be between 0 and 2"
        end

        Nodes::FuzzyCast.new(
          node,
          pdb_quoted(normalized_distance),
          prefix: prefix,
          transposition_cost_one: transposition_cost_one
        )
      end

      def pdb_apply_tokenizer(node, tokenizer)
        return node if tokenizer.nil?

        unless tokenizer.is_a?(String)
          raise ArgumentError, "tokenizer must be a string"
        end

        normalized = pdb_normalize_tokenizer(tokenizer)
        Nodes::TokenizerCast.new(node, normalized)
      end

      def pdb_apply_slop(node, slop)
        return node if slop.nil?

        pdb_validate_numeric!(slop, :slop)
        Nodes::SlopCast.new(node, pdb_quoted(slop))
      end

      def pdb_quoted(value)
        ::Arel::Nodes.build_quoted(value)
      end

      def pdb_join_terms(terms)
        joined = terms.flatten.compact.map(&:to_s).join(" ")
        raise ArgumentError, "at least one search term is required" if joined.strip.empty?

        joined
      end

      def pdb_validate_numeric!(value, name)
        return if value.nil?
        return if value.is_a?(Numeric)

        raise ArgumentError, "#{name} must be numeric, got #{value.class}"
      end

      def pdb_validate_integer!(value, name)
        return if value.is_a?(Integer)

        raise ArgumentError, "#{name} must be an integer"
      end

      def pdb_normalize_tokenizer(tokenizer)
        value = tokenizer.strip
        if value.empty?
          raise ArgumentError, "tokenizer cannot be blank"
        end
        unless TOKENIZER_EXPRESSION.match?(value)
          raise ArgumentError, "invalid tokenizer expression: #{tokenizer.inspect}"
        end

        ParadeDB::TokenizerSQL.qualify(value)
      end

      module_function

      def install!
        return if ::Arel::Predications.ancestors.include?(ParadeDB::Arel::Predications)

        ::Arel::Predications.include(ParadeDB::Arel::Predications)
      end
    end
  end
end
