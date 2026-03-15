# frozen_string_literal: true

require "spec_helper"

class StatementCacheProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
end

RSpec.describe "StatementCacheIntegrationTest" do
  before do
    skip "Statement cache integration tests require PostgreSQL" unless postgresql?
    ensure_paradedb_setup!
  end
  it "arel node identity in ast" do
    # Verifies that ParadeDB nodes allow Arel ASTs to be compared for equality,
    # which is a prerequisite for effective ActiveRecord statement caching.
    rel1 = StatementCacheProduct.search(:description).matching_all("shoes", boost: 2.0)
    rel2 = StatementCacheProduct.search(:description).matching_all("shoes", boost: 2.0)
    rel3 = StatementCacheProduct.search(:description).matching_all("shoes", boost: 3.0)

    assert_equal rel1.arel.ast, rel2.arel.ast
    assert_equal rel1.arel.ast.hash, rel2.arel.ast.hash

    refute_equal rel1.arel.ast, rel3.arel.ast
    refute_equal rel1.arel.ast.hash, rel3.arel.ast.hash
  end
  it "statement cache execution" do
    # Verifies that a cached statement containing ParadeDB nodes can be executed.
    cache = ActiveRecord::StatementCache.create(StatementCacheProduct.connection) do
      StatementCacheProduct.search(:description).matching_all("shoes", boost: 2.0)
    end

    results = cache.execute([], StatementCacheProduct.connection)
    refute_nil results
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.to_s.downcase.include?("postgres")
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
end
