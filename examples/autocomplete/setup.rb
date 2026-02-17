#!/usr/bin/env ruby
# frozen_string_literal: true

require "logger"
require "rails"
require "active_record"
require_relative "../../lib/parade_db"

class AutocompleteExampleApp < Rails::Application
  config.root = File.expand_path("../..", __dir__)
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.secret_key_base = "paradedb_examples_secret_key_base"
end

AutocompleteExampleApp.initialize!

require_relative "model"

module AutocompleteSetup
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

    MockItem.reset_column_information
    MockItem.count
  end

  def setup_autocomplete_table!
    setup_mock_items!
    conn = ActiveRecord::Base.connection

    puts "\nCreating autocomplete_items table..."
    conn.execute("DROP TABLE IF EXISTS autocomplete_items CASCADE;")
    conn.execute(<<~SQL)
      CREATE TABLE autocomplete_items (
        id INTEGER PRIMARY KEY,
        description TEXT NOT NULL,
        category VARCHAR(100) NOT NULL,
        rating INTEGER NOT NULL,
        in_stock BOOLEAN NOT NULL DEFAULT true,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    SQL
    puts "  + Table created"

    puts "\nCopying data from #{MockItem.table_name}..."
    conn.execute(<<~SQL)
      INSERT INTO autocomplete_items (id, description, category, rating, in_stock, created_at)
      SELECT id, description, category, rating, in_stock, created_at
      FROM #{MockItem.table_name};
    SQL

    count = conn.select_value("SELECT COUNT(*) FROM autocomplete_items").to_i
    puts "  + Copied #{count} products from #{MockItem.table_name}"

    puts "\nCreating autocomplete-optimized BM25 index..."
    conn.execute("DROP INDEX IF EXISTS autocomplete_items_idx;")
    conn.execute(<<~SQL)
      CREATE INDEX autocomplete_items_idx ON autocomplete_items
      USING bm25 (
        id,
        description,
        (description::pdb.ngram(3,8,'alias=description_ngram')),
        (category::pdb.literal('alias=category'))
      )
      WITH (key_field='id');
    SQL

    puts "  + Created BM25 index with:"
    puts "    - description (standard tokenizer)"
    puts "    - description_ngram (ngram 3-8 for substring matching)"
    puts "    - category (literal for exact matching)"

    count
  end
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "Autocomplete Setup - Creating Dedicated Table"
  puts "=" * 60

  count = AutocompleteSetup.setup_autocomplete_table!

  puts "\n" + "=" * 60
  puts "+ Setup complete! Created autocomplete_items with #{count} products"
  puts "=" * 60
  puts "\nRun: BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/autocomplete/autocomplete.rb"
end
