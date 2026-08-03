#!/usr/bin/env ruby
# frozen_string_literal: true

require "logger"
require "rails"
require "active_record"
require_relative "../../lib/parade_db"

class VectorSearchExampleApp < Rails::Application
  config.root = File.expand_path("../..", __dir__)
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.secret_key_base = "paradedb_examples_secret_key_base"
end

VectorSearchExampleApp.initialize!

require_relative "model"

module VectorSearchSetup
  module_function

  QUERY_SEED_TEXT = "Sleek running shoes"

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

  def setup!
    connect!

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search CASCADE;")
    conn.execute(
      "CALL paradedb.create_bm25_test_table(schema_name => 'public', table_name => 'mock_items');"
    )
    conn.remove_paradedb_index(:mock_items, name: :search_idx, if_exists: true)
    conn.create_paradedb_index(MockItemIndex)

    MockItem.reset_column_information
    MockItem.count
  end

  def query_embedding
    connect!

    embedding = MockItem.where.not(embedding: nil)
                        .search(:description)
                        .match_all(QUERY_SEED_TEXT)
                        .order(id: :asc)
                        .limit(1)
                        .pick(:embedding)
    raise "No embedding found for seed '#{QUERY_SEED_TEXT}'" if embedding.nil?

    embedding
  end
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "Vector Search Setup - Loading mock_items Table"
  puts "=" * 60

  count = VectorSearchSetup.setup!
  puts "+ Loaded #{count} mock items with pre-populated vector(8) embeddings"
  puts "\nSetup complete! Run: BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/vector_search/vector_search.rb"
end
