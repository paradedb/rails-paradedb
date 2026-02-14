# frozen_string_literal: true

require "minitest/autorun"
require "active_record"
require_relative "../lib/parade_db"

ActiveRecord::Base.logger = nil

def establish_test_connection
  return if ActiveRecord::Base.connected?

  dsn = ENV["PARADEDB_TEST_DSN"].to_s
  if dsn.empty?
    raise "PARADEDB_TEST_DSN is required for all tests. Example: postgres://postgres:postgres@localhost:5432/postgres"
  end

  ActiveRecord::Base.establish_connection(dsn)
  ParadeDB.ensure_postgresql_adapter!(ActiveRecord::Base.connection, context: "Test suite")
end

def setup_test_schema
  return if defined?($paradedb_schema_loaded) && $paradedb_schema_loaded

  establish_test_connection

  ActiveRecord::Schema.define do
    suppress_messages do
      create_table :products, force: true do |t|
        t.text :description
        t.text :category
        t.integer :rating
        t.boolean :in_stock
        t.integer :price
      end

      create_table :categories, force: true do |t|
        t.text :name
      end
    end
  end

  $paradedb_schema_loaded = true
end

establish_test_connection
setup_test_schema

def normalize_sql(sql)
  sql.to_s.strip
     .gsub(/\s+/, " ")
     .gsub(/"/, "")
     .gsub(/\bTRUE\b/i, "true")
     .gsub(/\bFALSE\b/i, "false")
     .gsub(/\(\s*([A-Za-z0-9_\.]+)\s*=\s*(true|false)\s*\)/i, '\\1 = \\2')
end

def assert_sql_equal(expected, actual)
  assert_equal normalize_sql(expected), normalize_sql(actual)
end
