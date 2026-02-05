# frozen_string_literal: true

require "spec_helper"

class BehaviorProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

class UserApiBehaviorIntegrationTest < Minitest::Test
  def setup
    skip "Behavior integration tests require PostgreSQL" unless postgresql?

    ensure_paradedb_setup!
    seed_products!
  end

  def test_matching_all_executes_and_returns_rows
    ids = BehaviorProduct.search(:description)
                         .matching_all("running", "shoes")
                         .order(:id)
                         .pluck(:id)

    assert_equal [1, 2], ids
  end

  def test_matching_any_executes_and_returns_rows
    ids = BehaviorProduct.search(:description)
                         .matching_any("wireless", "hiking")
                         .order(:id)
                         .pluck(:id)

    assert_equal [3, 5], ids
  end

  def test_phrase_near_and_phrase_prefix_execute
    phrase_ids = BehaviorProduct.search(:description).phrase("running shoes").order(:id).pluck(:id)
    near_ids = BehaviorProduct.search(:description).near("running", "shoes", distance: 1).order(:id).pluck(:id)
    prefix_ids = BehaviorProduct.search(:category).phrase_prefix("foot").order(:id).pluck(:id)

    assert_equal [1, 2], phrase_ids
    assert_equal [1, 2], near_ids
    assert_equal [1, 2, 5], prefix_ids
  end

  def test_term_regex_and_fuzzy_execute
    term_ids = BehaviorProduct.search(:category).term("audio").order(:id).pluck(:id)
    regex_ids = BehaviorProduct.search(:description).regex("run.*").order(:id).pluck(:id)
    fuzzy_ids = BehaviorProduct.search(:description).fuzzy("shose", distance: 2).order(:id).pluck(:id)

    assert_equal [3, 4], term_ids
    assert_equal [1, 2, 6], regex_ids
    assert_equal [1, 2], fuzzy_ids
  end

  def test_more_like_this_executes_and_returns_similar_rows
    ids = BehaviorProduct.more_like_this(3, fields: [:description]).limit(5).pluck(:id)

    assert_includes ids, 4
  end

  def test_with_score_and_with_snippet_materialize_columns
    rows = BehaviorProduct.search(:description)
                          .matching_all("running shoes")
                          .with_score
                          .with_snippet(:description, start_tag: "<b>", end_tag: "</b>", max_chars: 60)
                          .order(:id)
                          .to_a

    refute_empty rows
    rows.each do |row|
      refute_nil row.search_score
      refute_nil row.description_snippet
    end
  end

  def test_facets_and_with_facets_execute_and_parse_results
    facet_hash = BehaviorProduct.search(:description).matching_all("earbuds").facets(:rating)
    assert_kind_of Hash, facet_hash
    assert_includes facet_hash, "rating"
    assert_match(/[35]/, facet_hash["rating"].to_json)

    rel = BehaviorProduct.search(:description)
                         .matching_all("running shoes")
                         .with_facets(:rating, size: 10)
                         .order(:id)
                         .limit(10)
    rows = rel.to_a
    assert_equal [1, 2], rows.map(&:id)

    rel_facets = rel.facets
    assert_kind_of Hash, rel_facets
    assert_includes rel_facets, "rating"
    assert_match(/[45]/, rel_facets["rating"].to_json)
  end

  def test_with_facets_without_topn_shape_raises_friendly_error
    rel = BehaviorProduct.search(:description).matching_all("running shoes").with_facets(:rating, size: 10)
    error = assert_raises(ParadeDB::FacetQueryError) { rel.to_a }
    assert_includes error.message, "ORDER BY and LIMIT"
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
    conn = ActiveRecord::Base.connection
    conn.execute("TRUNCATE TABLE products RESTART IDENTITY;")

    BehaviorProduct.create!(description: "running shoes lightweight", category: "footwear", rating: 5, in_stock: true, price: 120)
    BehaviorProduct.create!(description: "trail running shoes grip", category: "footwear", rating: 4, in_stock: true, price: 90)
    BehaviorProduct.create!(description: "wireless bluetooth earbuds", category: "audio", rating: 5, in_stock: true, price: 80)
    BehaviorProduct.create!(description: "budget wired earbuds", category: "audio", rating: 3, in_stock: false, price: 20)
    BehaviorProduct.create!(description: "hiking boots waterproof", category: "footwear", rating: 4, in_stock: true, price: 110)
    BehaviorProduct.create!(description: "running socks breathable", category: "apparel", rating: 2, in_stock: true, price: 15)
  end
end
