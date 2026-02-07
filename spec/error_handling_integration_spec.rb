# frozen_string_literal: true

require "spec_helper"

class ErrorHandlingProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

class ErrorHandlingIntegrationTest < Minitest::Test
  def setup
    skip "Error-handling integration tests require PostgreSQL" unless postgresql?

    ensure_paradedb_setup!
    seed_products!
  end

  def test_invalid_parse_query_raises_statement_invalid
    error = assert_raises(ActiveRecord::StatementInvalid) do
      ErrorHandlingProduct.search(:description).parse("AND AND invalid").to_a
    end
    assert_match(/parse|syntax|query/i, error.message)
  end

  def test_invalid_regex_query_raises_statement_invalid
    error = assert_raises(ActiveRecord::StatementInvalid) do
      ErrorHandlingProduct.search(:description).regex("[invalid(regex").to_a
    end
    assert_match(/regex|invalid/i, error.message)
  end

  def test_more_like_this_nonexistent_id_returns_empty
    ids = ErrorHandlingProduct.more_like_this(999_999, fields: [:description]).order(:id).pluck(:id)
    assert_equal [], ids
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end

  def ensure_paradedb_setup!
    return if self.class.instance_variable_get(:@paradedb_setup_done)

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.execute("DROP INDEX IF EXISTS products_bm25_idx;")
    conn.execute(<<~SQL)
      CREATE INDEX products_bm25_idx ON products
      USING bm25 (id, description, category, rating, in_stock, price)
      WITH (key_field='id');
    SQL

    self.class.instance_variable_set(:@paradedb_setup_done, true)
  end

  def seed_products!
    ErrorHandlingProduct.connection.execute("TRUNCATE TABLE products RESTART IDENTITY;")
    ErrorHandlingProduct.create!(description: "running shoes lightweight", category: "footwear", rating: 5, in_stock: true, price: 120)
    ErrorHandlingProduct.create!(description: "trail running shoes grip", category: "footwear", rating: 4, in_stock: true, price: 90)
    ErrorHandlingProduct.create!(description: "wireless bluetooth earbuds", category: "audio", rating: 5, in_stock: true, price: 80)
    ErrorHandlingProduct.create!(description: "budget wired earbuds", category: "audio", rating: 3, in_stock: false, price: 20)
  end
end
