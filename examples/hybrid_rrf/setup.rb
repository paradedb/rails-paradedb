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

  def setup_mock_items!
    connect!

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.execute(
      "CALL paradedb.create_bm25_test_table(schema_name => 'public', table_name => 'mock_items');"
    )
    conn.execute("DROP TABLE IF EXISTS mock_items_hybrid_rrf CASCADE;")
    conn.execute("CREATE TABLE mock_items_hybrid_rrf AS TABLE mock_items;")
    conn.remove_bm25_index(:mock_items_hybrid_rrf, name: :mock_items_hybrid_rrf_bm25_idx, if_exists: true)
    conn.create_paradedb_index(MockItemIndex, if_not_exists: true)

    MockItem.reset_column_information
    MockItem.count
  end

  def embeddings_csv_path
    File.expand_path("mock_items_embeddings.csv", __dir__)
  end

  def load_embeddings_from_csv(path = embeddings_csv_path)
    embeddings = {}

    File.foreach(path).with_index do |line, index|
      next if index.zero?

      raw = line.strip
      next if raw.empty?

      id_part, _description, embedding_part = raw.split(",", 3)
      next unless id_part && embedding_part

      embedding_literal = embedding_part
      if embedding_literal.start_with?("\"") && embedding_literal.end_with?("\"")
        embedding_literal = embedding_literal[1..-2]
      end

      embeddings[id_part.to_i] = embedding_literal
    end

    embeddings
  end

  def setup!
    count = setup_mock_items!

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    conn.execute(<<~SQL)
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = '#{MockItem.table_name}' AND column_name = 'embedding'
        ) THEN
          ALTER TABLE #{MockItem.table_name} ADD COLUMN embedding vector(384);
        END IF;
      END $$;
    SQL

    MockItem.reset_column_information

    existing = conn.select_value("SELECT COUNT(*) FROM #{MockItem.table_name} WHERE embedding IS NOT NULL").to_i
    if existing.positive?
      puts "+ #{existing} items already have embeddings"
      return count
    end

    path = embeddings_csv_path
    unless File.exist?(path)
      warn "Embedding CSV not found: #{path}"
      return count
    end

    puts "Loading embeddings from #{path}..."
    embeddings = load_embeddings_from_csv(path)
    total = embeddings.length
    puts "Found #{total} embeddings in CSV"

    embeddings.each_with_index do |(id, vector_literal), index|
      conn.execute(
        "UPDATE #{MockItem.table_name} SET embedding = #{conn.quote(vector_literal)}::vector WHERE id = #{id.to_i};"
      )

      current = index + 1
      puts "  [#{current}/#{total}]" if (current % 10).zero? || current == total
    end

    puts "+ Loaded #{total} embeddings"
    count
  end

  def query_embedding_for(query)
    seed_text = QUERY_SEED_TEXT[query.to_s.downcase.strip]
    raise "No query embedding seed configured for '#{query}'" unless seed_text

    connect!
    embedding = MockItem.where.not(embedding: nil)
                        .search(:description)
                        .matching_all(seed_text)
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
  puts "Hybrid Search Setup - Loading Embeddings from CSV"
  puts "=" * 60

  HybridRrfSetup.setup!

  puts "\nSetup complete! Run: BUNDLE_GEMFILE=examples/hybrid_rrf/Gemfile bundle exec ruby examples/hybrid_rrf/hybrid_rrf.rb"
end
