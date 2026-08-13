#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "logger"
require "rails"
require "active_record"
require_relative "../../lib/parade_db"

class HybridRrfExampleApp < Rails::Application
  config.root = File.expand_path("../..", __dir__)
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.secret_key_base = "paradedb_examples_secret_key_base"
end

HybridRrfExampleApp.initialize!

require_relative "model"

module HybridRrfSetup
  module_function

  QUERY_SEED_TEXT = {
    "running shoes" => "Sleek running shoes",
    "footwear for exercise" => "Sleek running shoes",
    "wireless earbuds" => "Innovative wireless earbuds"
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

  def setup!
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
    seed_text = QUERY_SEED_TEXT[query.to_s.downcase.strip]
    raise "No query embedding seed configured for '#{query}'" unless seed_text

    connect!
    embedding = MockItem.where.not(embedding: nil)
                        .search(:description)
                        .match_all(seed_text)
                        .order(id: :asc)
                        .limit(1)
                        .pick(:embedding)
    raise "No embedding found for seed '#{seed_text}'" if embedding.nil?

    normalize_embedding(embedding)
  end

  def normalize_embedding(value)
    return value if value.is_a?(Array)
    return JSON.parse(value) if value.is_a?(String)

    if value.respond_to?(:to_a)
      as_array = value.to_a
      return as_array if as_array.is_a?(Array)
    end

    raise "Unsupported embedding value type: #{value.class}"
  rescue JSON::ParserError => e
    raise "Invalid embedding payload for query seed: #{e.message}"
  end
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "Hybrid Search Setup"
  puts "=" * 60

  count = HybridRrfSetup.setup!
  puts "+ Loaded #{count} mock items with pre-populated embeddings"

  puts "\nSetup complete! Run: BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/hybrid_rrf/hybrid_rrf.rb"
end
