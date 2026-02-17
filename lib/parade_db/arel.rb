# frozen_string_literal: true

require "active_record"

require_relative "arel/nodes"
require_relative "arel/visitor"
require_relative "arel/builder"

module ParadeDB
  module Arel
    # Convenience helper to render any ParadeDB Arel node to SQL.
    def self.to_sql(node, connection = nil)
      conn = connection || ::ActiveRecord::Base.connection
      ParadeDB.ensure_postgresql_adapter!(conn, context: "ParadeDB::Arel.to_sql")

      collector = ::Arel::Collectors::SQLString.new
      conn.visitor.accept(node, collector).value
    end

    # Helper to wrap raw SQL without quoting.
    def self.sql(raw)
      ::Arel.sql(raw)
    end
  end
end
