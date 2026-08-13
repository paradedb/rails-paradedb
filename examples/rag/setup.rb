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

  QUERY_SEED_TEXT = {
    "What running shoes do you have?" => "Sleek running shoes",
    "I need comfortable shoes for everyday use" => "Sleek running shoes",
    "Do you have any wireless audio products?" => "Innovative wireless earbuds"
  }.freeze

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
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search CASCADE;")
    conn.drop_table(:mock_items, if_exists: true)
    conn.execute(
      "CALL paradedb.create_bm25_test_table(schema_name => 'public', table_name => 'mock_items');"
    )
    conn.remove_paradedb_index(:mock_items, name: :search_idx, if_exists: true)
    conn.create_paradedb_index(MockItemIndex)

    MockItem.reset_column_information
    MockItem.count
  end

  def query_embedding_for(query)
    seed_text = QUERY_SEED_TEXT[query.to_s.strip]
    raise "No query embedding seed configured for '#{query}'" unless seed_text

    connect!
    embedding = MockItem.where.not(embedding: nil)
                        .search(:description)
                        .match_all(seed_text)
                        .order(id: :asc)
                        .limit(1)
                        .pick(:embedding)
    raise "No embedding found for seed '#{seed_text}'" if embedding.nil?

    embedding
  end
end
