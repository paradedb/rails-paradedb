# frozen_string_literal: true

module ParadeDB
  module Arel
    module Nodes
      class BoostCast < ::Arel::Nodes::Node
        attr_reader :expr, :factor

        def initialize(expr, factor)
          @expr = expr
          @factor = factor
        end
      end

      class SlopCast < ::Arel::Nodes::Node
        attr_reader :expr, :distance

        def initialize(expr, distance)
          @expr = expr
          @distance = distance
        end
      end

      class FuzzyCast < ::Arel::Nodes::Node
        attr_reader :expr, :distance, :prefix

        def initialize(expr, distance, prefix: nil)
          @expr = expr
          @distance = distance
          @prefix = prefix
        end
      end

      class ArrayLiteral < ::Arel::Nodes::Node
        attr_reader :values

        def initialize(values)
          @values = Array(values)
        end
      end

      class ParseNode < ::Arel::Nodes::Node
        attr_reader :query, :lenient

        def initialize(query, lenient: nil)
          @query = query
          @lenient = lenient
        end
      end
    end
  end
end
