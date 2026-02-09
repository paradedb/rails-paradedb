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
        attr_reader :expr, :distance, :prefix

        def initialize(expr, distance, prefix: nil)
          @expr = expr
          @distance = distance
          @prefix = prefix
        end

        def hash
          [self.class, expr, distance, prefix].hash
        end

        def eql?(other)
          self.class == other.class &&
            expr == other.expr &&
            distance == other.distance &&
            prefix == other.prefix
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

      class ParseNode < ::Arel::Nodes::Node
        attr_reader :query, :lenient

        def initialize(query, lenient: nil)
          @query = query
          @lenient = lenient
        end

        def hash
          [self.class, query, lenient].hash
        end

        def eql?(other)
          self.class == other.class &&
            query == other.query &&
            lenient == other.lenient
        end
        alias == eql?
      end
    end
  end
end
# rubocop:enable Lint/MissingSuper
