# frozen_string_literal: true

require_relative "arel/nodes"
require_relative "arel/visitor"
require_relative "arel/builder"

module ParadeDB
  module Arel
    # Convenience helper to render any ParadeDB Arel node to SQL.
    def self.to_sql(node, connection = nil)
      Visitor.new(connection).accept(node)
    end

    # Helper to wrap raw SQL without quoting.
    def self.sql(raw)
      Nodes::SqlLiteral.new(raw)
    end
  end
end

# Extend Arel nodes to be compatible with ActiveRecord::Relation.where()
module Arel
  module Predications
    # Allow ParadeDB nodes to be used directly in where() clauses
  end
end

# Make ParadeDB nodes respond to to_sql for ActiveRecord compatibility
ParadeDB::Arel::Nodes::Node.class_eval do
  def to_sql(connection = nil)
    ParadeDB::Arel.to_sql(self, connection)
  end
end
