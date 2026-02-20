# frozen_string_literal: true

require "logger"
require "rails"
require "active_record"
require_relative "../../lib/parade_db"

class RagExampleApp < Rails::Application
  config.root = File.expand_path("../..", __dir__)
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.secret_key_base = "paradedb_examples_secret_key_base"
end

RagExampleApp.initialize!

require_relative "model"

module RagSetup
  module_function

  def drop_bm25_indexes!(conn, table_name)
    indexes = conn.select_values(<<~SQL)
      SELECT indexname
      FROM pg_indexes
      WHERE schemaname = 'public'
        AND tablename = #{conn.quote(table_name.to_s)}
        AND indexdef LIKE '%USING bm25%'
    SQL

    indexes.each do |index_name|
      conn.execute("DROP INDEX IF EXISTS #{conn.quote_table_name(index_name)}")
    end
  end

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
    drop_bm25_indexes!(conn, :mock_items)
    conn.create_paradedb_index(MockItemIndex, if_not_exists: true)

    MockItem.reset_column_information
    MockItem.count
  end
end
