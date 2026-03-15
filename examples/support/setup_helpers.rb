# frozen_string_literal: true

module ParadeDBExamples
  module SetupHelpers
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

    def prepare_mock_items_source_table!
      connect!

      conn = ActiveRecord::Base.connection
      conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
      conn.execute(
        "CALL paradedb.create_bm25_test_table(schema_name => 'public', table_name => 'mock_items');"
      )
      conn
    end

    def recreate_mock_items_copy!(table_name)
      conn = prepare_mock_items_source_table!
      quoted_name = conn.quote_table_name(table_name.to_s)
      conn.execute("DROP TABLE IF EXISTS #{quoted_name} CASCADE;")
      conn.execute("CREATE TABLE #{quoted_name} AS TABLE mock_items;")
      conn
    end

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
  end
end
