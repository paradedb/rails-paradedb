# frozen_string_literal: true
# rubocop:disable Lint/MissingSuper

module ParadeDB
  module Arel
    module Nodes
      class BoostCast < ::Arel::Nodes::Node
        attr_reader :expr, :factor

        def initialize(expr, factor)
          @expr = expr
          @factor = factor
        end

        def hash
          [self.class, expr, factor].hash
        end

        def eql?(other)
          self.class == other.class &&
            expr == other.expr &&
            factor == other.factor
        end
        alias == eql?
      end

      class ConstCast < ::Arel::Nodes::Node
        attr_reader :expr, :score

        def initialize(expr, score)
          @expr = expr
          @score = score
        end

        def hash
          [self.class, expr, score].hash
        end

        def eql?(other)
          self.class == other.class &&
            expr == other.expr &&
            score == other.score
        end
        alias == eql?
      end

      class QueryCast < ::Arel::Nodes::Node
        attr_reader :expr

        def initialize(expr)
          @expr = expr
        end

        def hash
          [self.class, expr].hash
        end

        def eql?(other)
          self.class == other.class &&
            expr == other.expr
        end
        alias == eql?
      end

      class SlopCast < ::Arel::Nodes::Node
        attr_reader :expr, :distance

        def initialize(expr, distance)
          @expr = expr
          @distance = distance
        end

        def hash
          [self.class, expr, distance].hash
        end

        def eql?(other)
          self.class == other.class &&
            expr == other.expr &&
            distance == other.distance
        end
        alias == eql?
      end

      class FuzzyCast < ::Arel::Nodes::Node
        attr_reader :expr, :distance, :prefix, :transposition_cost_one

        def initialize(expr, distance, prefix: nil, transposition_cost_one: nil)
          @expr = expr
          @distance = distance
          @prefix = prefix
          @transposition_cost_one = transposition_cost_one
        end

        def hash
          [self.class, expr, distance, prefix, transposition_cost_one].hash
        end

        def eql?(other)
          self.class == other.class &&
            expr == other.expr &&
            distance == other.distance &&
            prefix == other.prefix &&
            transposition_cost_one == other.transposition_cost_one
        end
        alias == eql?
      end

      class ArrayLiteral < ::Arel::Nodes::Node
        attr_reader :values

        def initialize(values)
          @values = Array(values)
        end

        def hash
          [self.class, values].hash
        end

        def eql?(other)
          self.class == other.class &&
            values == other.values
        end
        alias == eql?
      end

      class TokenizerCast < ::Arel::Nodes::Node
        attr_reader :expr, :tokenizer_sql

        def initialize(expr, tokenizer_sql)
          @expr = expr
          @tokenizer_sql = tokenizer_sql
        end

        def hash
          [self.class, expr, tokenizer_sql].hash
        end

        def eql?(other)
          self.class == other.class &&
            expr == other.expr &&
            tokenizer_sql == other.tokenizer_sql
        end
        alias == eql?
      end

      class ParseNode < ::Arel::Nodes::Node
        attr_reader :query, :lenient, :conjunction_mode

        def initialize(query, lenient: nil, conjunction_mode: nil)
          @query = query
          @lenient = lenient
          @conjunction_mode = conjunction_mode
        end

        def hash
          [self.class, query, lenient, conjunction_mode].hash
        end

        def eql?(other)
          self.class == other.class &&
            query == other.query &&
            lenient == other.lenient &&
            conjunction_mode == other.conjunction_mode
        end
        alias == eql?
      end
    end
  end
end
# rubocop:enable Lint/MissingSuper
