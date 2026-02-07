#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

require_relative "../common"

module HybridRrfSetup
  module_function

  QUERY_SEED_TEXT = {
    "running shoes" => "Sleek running shoes",
    "footwear for exercise" => "Sleek running shoes",
    "wireless earbuds" => "Innovative wireless earbuds"
  }.freeze

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
    count = ExampleCommon.setup_mock_items!

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    conn.execute(<<~SQL)
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_name = 'mock_items' AND column_name = 'embedding'
        ) THEN
          ALTER TABLE mock_items ADD COLUMN embedding vector(384);
        END IF;
      END $$;
    SQL

    MockItem.reset_column_information

    existing = conn.select_value("SELECT COUNT(*) FROM mock_items WHERE embedding IS NOT NULL").to_i
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
        "UPDATE mock_items SET embedding = #{conn.quote(vector_literal)}::vector WHERE id = #{id.to_i};"
      )

      current = index + 1
      if (current % 10).zero? || current == total
        puts "  [#{current}/#{total}]"
      end
    end

    puts "+ Loaded #{total} embeddings"
    count
  end

  # Resolve a demo query to a stable seed document embedding.
  # Returns an Array<Float> for neighbor's nearest_neighbors API.
  def query_embedding_for(query)
    seed_text = QUERY_SEED_TEXT[query.to_s.downcase.strip]
    raise "No query embedding seed configured for '#{query}'" unless seed_text

    ExampleCommon.connect!
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

  puts "\nSetup complete! Run: bundle exec ruby examples/hybrid_rrf/hybrid_rrf.rb"
end
