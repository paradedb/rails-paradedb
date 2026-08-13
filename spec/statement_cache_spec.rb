# frozen_string_literal: true

require "spec_helper"

class StatementCacheProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :mock_items
end

RSpec.describe "StatementCache" do
  before(:context) do
    setup_test_index
  end
  it "arel node identity in ast" do
    # Verifies that ParadeDB query expressions allow relation ASTs to be compared for equality,
    # which is a prerequisite for effective ActiveRecord statement caching.
    rel1 = StatementCacheProduct.search(:description).match_all(ParadeDB.boost("shoes", 2.0))
    rel2 = StatementCacheProduct.search(:description).match_all(ParadeDB.boost("shoes", 2.0))
    rel3 = StatementCacheProduct.search(:description).match_all(ParadeDB.boost("shoes", 3.0))

    assert_equal rel1.arel.ast, rel2.arel.ast
    assert_equal rel1.arel.ast.hash, rel2.arel.ast.hash

    refute_equal rel1.arel.ast, rel3.arel.ast
    refute_equal rel1.arel.ast.hash, rel3.arel.ast.hash
  end
  it "statement cache execution" do
    # Verifies that a cached statement containing ParadeDB nodes can be executed.
    cache = ActiveRecord::StatementCache.create(StatementCacheProduct.connection) do
      StatementCacheProduct.search(:description).match_all(ParadeDB.boost("shoes", 2.0))
    end

    results = cache.execute([], StatementCacheProduct.connection)
    refute_nil results
  end
end
