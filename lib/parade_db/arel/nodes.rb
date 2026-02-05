# frozen_string_literal: true

module ParadeDB
  module Arel
    module Nodes
      class Node
        def and(other)
          And.new(self, other)
        end

        def or(other)
          Or.new(self, other)
        end

        def not
          Not.new(self)
        end
      end

      # Basic node shapes
      class Binary < Node
        attr_reader :left, :right

        def initialize(left, right)
          @left = left
          @right = right
        end
      end

      class Unary < Node
        attr_reader :expr

        def initialize(expr)
          @expr = expr
        end
      end

      class Function < Node
        attr_reader :name, :args

        def initialize(name, *args)
          @name = name
          @args = args
        end
      end

      # Boolean nodes
      class And < Binary; end
      class Or < Binary; end
      class Not < Unary; end

      # Leaf/utility nodes
      class SqlLiteral < Node
        attr_reader :value

        def initialize(value)
          @value = value
        end
      end

      class Attribute < Node
        attr_reader :name, :table

        def initialize(name, table: nil)
          @name = name
          @table = table
        end
      end

      class Value < Node
        attr_reader :value

        def initialize(value)
          @value = value
        end
      end

      # ParadeDB-specific AST nodes
      class Match < Binary; end                  # left &&& right
      class MatchAny < Binary; end               # left ||| right
      class Phrase < Binary; end                 # left ### right
      class Term < Binary; end                   # left === right (exact term)
      class Fuzzy < Binary
        attr_reader :distance, :prefix, :boost

        def initialize(left, right, distance:, prefix: nil, boost: nil)
          super(left, right)
          @distance = distance
          @prefix = prefix
          @boost = boost
        end
      end
      class FullText < Binary; end               # left @@@ right (generic)
      class Regex < Binary; end                  # left @@@ pdb.regex(pattern)
      class Near < Binary
        attr_reader :distance

        def initialize(left, terms:, distance:)
          raise ArgumentError, "terms must be 2 items" unless terms.is_a?(Array) && terms.size == 2
          super(left, terms)
          @distance = distance
        end
      end
      class PhrasePrefix < Binary; end           # left @@@ pdb.phrase_prefix(...)
      class MoreLikeThis < Binary
        attr_reader :fields

        def initialize(left, key, fields: nil)
          super(left, key)
          @fields = fields
        end
      end

      # Projections / functions
      class Score < Function; end                # pdb.score(key)
      class Snippet < Function; end              # pdb.snippet(column, ...)
      class Agg < Function; end                  # pdb.agg(json)

      # Modifiers
      class Boost < Unary
        attr_reader :factor

        def initialize(expr, factor)
          super(expr)
          @factor = factor
        end
      end

      class Slop < Unary
        attr_reader :distance

        def initialize(expr, distance)
          super(expr)
          @distance = distance
        end
      end
    end
  end
end
