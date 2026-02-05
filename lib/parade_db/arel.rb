# frozen_string_literal: true

require_relative "arel/nodes"
require_relative "arel/visitor"
require_relative "arel/builder"

module ParadeDB
  module Arel
    # Convenience helper to render any ParadeDB Arel node to SQL.
    def self.to_sql(node)
      Visitor.new.accept(node)
    end

    # Helper to wrap raw SQL without quoting.
    def self.sql(raw)
      Nodes::SqlLiteral.new(raw)
    end
  end
end
