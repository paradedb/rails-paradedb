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

  SEED_ITEMS = [
    { description: "Sleek running shoes", category: "Footwear", embedding: [1.0, 0.1, 0.0] },
    { description: "Trail running shoes with grip", category: "Footwear", embedding: [0.9, 0.2, 0.1] },
    { description: "White leather sneakers", category: "Footwear", embedding: [0.7, 0.4, 0.2] },
    { description: "Innovative wireless earbuds", category: "Electronics", embedding: [0.0, 1.0, 0.1] },
    { description: "Over-ear noise cancelling headphones", category: "Electronics", embedding: [0.1, 0.9, 0.2] },
    { description: "Portable bluetooth speaker", category: "Electronics", embedding: [0.2, 0.8, 0.4] },
    { description: "Insulated camping tent", category: "Outdoor", embedding: [0.1, 0.2, 1.0] },
    { description: "Lightweight hiking backpack", category: "Outdoor", embedding: [0.3, 0.1, 0.9] }
  ].freeze

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
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")

    conn.execute("DROP TABLE IF EXISTS vector_items CASCADE;")
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :vector_items, force: true do |t|
          t.text :description
          t.text :category
          t.vector :embedding, limit: 3
        end
      end
    end

    VectorItem.reset_column_information
    SEED_ITEMS.each { |attrs| VectorItem.create!(attrs) }

    conn.create_paradedb_index(VectorItemIndex, if_not_exists: true)
    VectorItem.count
  end
end

if $PROGRAM_NAME == __FILE__
  puts "=" * 60
  puts "Vector Search Setup - Creating vector_items Table"
  puts "=" * 60

  count = VectorSearchSetup.setup!
  puts "+ Seeded #{count} items with vector(3) embeddings"
  puts "\nSetup complete! Run: BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/vector_search/vector_search.rb"
end
