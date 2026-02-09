# frozen_string_literal: true

begin
  require "neighbor"
rescue LoadError
  abort "Examples require neighbor. Run with `BUNDLE_GEMFILE=examples/Gemfile bundle exec ...`."
end

require "active_record"
require_relative "../lib/parade_db"

class MockItemIndex < ParadeDB::Index
  self.table_name = :mock_items
  self.key_field = :id
  self.fields = [
    :id,
    :description,
    :rating,
    { category: { literal: { alias: "category" } } },
    { "metadata->>'color'" => { literal: { alias: "metadata_color" } } },
    { "metadata->>'location'" => { literal: { alias: "metadata_location" } } }
  ]
end

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
    conn.remove_bm25_index(:mock_items, if_exists: true)
    conn.create_paradedb_index(MockItemIndex)

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
