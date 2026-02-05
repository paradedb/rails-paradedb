# frozen_string_literal: true

require "active_record"
require_relative "../lib/parade_db"

module ExampleCommon
  module_function

  def database_url
    return ENV["DATABASE_URL"] if ENV["DATABASE_URL"]

    host = ENV.fetch("PGHOST", "localhost")
    port = ENV.fetch("PGPORT", "5432")
    user = ENV.fetch("PGUSER", "postgres")
    password = ENV.fetch("PGPASSWORD", "postgres")
    database = ENV.fetch("PGDATABASE", "postgres")

    "postgresql://#{user}:#{password}@#{host}:#{port}/#{database}"
  end

  def connect!
    return if ActiveRecord::Base.connected?

    ActiveRecord::Base.establish_connection(database_url)
    ActiveRecord::Base.logger = nil
  end

  def setup_mock_items!
    connect!

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.execute(
      "CALL paradedb.create_bm25_test_table(schema_name => 'public', table_name => 'mock_items');"
    )
    conn.execute("DROP INDEX IF EXISTS mock_items_bm25_idx;")
    conn.execute(<<~SQL)
      CREATE INDEX mock_items_bm25_idx ON mock_items USING bm25 (
        id,
        description,
        rating,
        (category::pdb.literal('alias=category')),
        ((metadata->>'color')::pdb.literal('alias=metadata_color')),
        ((metadata->>'location')::pdb.literal('alias=metadata_location'))
      ) WITH (key_field='id');
    SQL

    MockItem.reset_column_information
    MockItem.count
  end

end

class MockItem < ActiveRecord::Base
  include ParadeDB::Model

  self.table_name = "mock_items"
  self.primary_key = "id"
  self.has_paradedb_index = true
end
