# frozen_string_literal: true

require "spec_helper"

class Product < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

class Category < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :categories
  self.has_paradedb_index = true
end

class UserApiIntegrationTest < Minitest::Test
  def setup
    skip "Integration tests require PostgreSQL" unless postgresql?

    ensure_paradedb_setup!
    seed_products!
  end

  def test_matching_all_with_filters_executes
    ids = Product.search(:description)
                 .matching_all("running", "shoes")
                 .where(in_stock: true)
                 .where("products.price < 100")
                 .where(rating: 4..)
                 .order(:id)
                 .pluck(:id)

    assert_equal [2], ids
  end

  def test_range_filters_execute
    closed = Product.search(:description).matching_all("shoes").where(price: 90..120).order(:id).pluck(:id)
    exclusive = Product.search(:description).matching_all("shoes").where(price: 90...120).order(:id).pluck(:id)

    assert_equal [1, 2], closed
    assert_equal [2], exclusive
  end

  def test_chain_multiple_search_fields_with_and_executes
    ids = Product.search(:description).matching_all("running", "shoes")
                 .search(:category).phrase("footwear")
                 .order(:id)
                 .pluck(:id)

    assert_equal [1, 2], ids
  end

  def test_matching_any_excluding_phrase_fuzzy_regex_term_near_prefix_parse_match_all_execute
    assert_equal [3, 5], Product.search(:description).matching_any("wireless", "hiking").order(:id).pluck(:id)
    assert_equal [1], Product.search(:description).matching_all("shoes").excluding("trail").order(:id).pluck(:id)
    assert_equal [1, 2], Product.search(:description).phrase("running shoes").order(:id).pluck(:id)
    assert_equal [1, 2], Product.search(:description).fuzzy("shose", distance: 2).order(:id).pluck(:id)
    assert_equal [1, 2, 6], Product.search(:description).regex("run.*").order(:id).pluck(:id)
    assert_equal [3, 4], Product.search(:category).term("audio").order(:id).pluck(:id)
    assert_equal [1, 2], Product.search(:description).near("running", "shoes", distance: 1).order(:id).pluck(:id)
    assert_equal [1, 2, 5], Product.search(:category).phrase_prefix("foot").order(:id).pluck(:id)
    assert_equal [1, 2], Product.search(:description).parse("running AND shoes", lenient: true).order(:id).pluck(:id)
    assert_equal [1, 2, 3], Product.search(:id).match_all.order(:id).limit(3).pluck(:id)
  end

  def test_more_like_this_executes
    ids = Product.more_like_this(3, fields: [:description]).order(:id).pluck(:id)
    assert_includes ids, 4
  end

  def test_with_score_and_snippet_projections_execute
    rows = Product.search(:description)
                  .matching_all("running shoes")
                  .with_score
                  .with_snippet(:description, start_tag: "<mark>", end_tag: "</mark>", max_chars: 80)
                  .order(search_score: :desc)
                  .limit(3)
                  .to_a

    refute_empty rows
    rows.each do |row|
      refute_nil row.search_score
      refute_nil row.description_snippet
      assert_includes row.description_snippet, "<mark>"
    end
  end

  def test_or_across_fields_with_base_scope_executes
    base = Product.where(in_stock: true)
    left = base.search(:description).matching_all("shoes")
    right = base.search(:category).matching_all("footwear")

    ids = left.or(right).order(:id).pluck(:id)
    assert_equal [1, 2, 5], ids
  end

  def test_facets_only_executes
    facets = Product.search(:description).matching_all("shoes").facets(:rating, size: 10)

    assert_kind_of Hash, facets
    assert_includes facets, "rating"
  end

  def test_with_facets_rows_plus_facets_executes
    relation = Product.search(:description).matching_all("shoes")
                      .where(in_stock: true)
                      .with_facets(:rating, size: 10)
                      .order(rating: :desc)
                      .limit(10)

    rows = relation.to_a
    assert_equal [1, 2], rows.map(&:id).sort

    facets = relation.facets
    assert_includes facets, "rating"
  end

  def test_search_on_scoped_relation_preserves_scope_semantics
    ids = Product.where(in_stock: true)
                 .where(price: 10..100)
                 .search(:description)
                 .matching_all("wireless")
                 .order(:id)
                 .pluck(:id)

    assert_equal [3], ids
  end

  def test_search_with_joins_executes
    ids = Product.joins("INNER JOIN categories ON categories.name = products.category")
                 .search(:description)
                 .matching_all("running")
                 .where(categories: { name: "footwear" })
                 .order(:id)
                 .pluck(:id)

    assert_equal [1, 2], ids
  end

  def test_search_with_group_and_having_executes
    rows = Product.search(:description)
                  .matching_all("running")
                  .group(:category)
                  .having("COUNT(*) >= 2")
                  .order(:category)
                  .pluck(:category, Arel.sql("COUNT(*)::int"))

    assert_equal [["footwear", 2]], rows
  end

  def test_search_with_distinct_and_not_and_in_executes
    distinct_ids = Product.search(:description).matching_all("shoes").distinct.order(:id).pluck(:id)
    not_ids = Product.search(:description).matching_all("shoes").where.not(category: "audio").order(:id).pluck(:id)
    in_ids = Product.search(:description).matching_all("wireless").where(category: %w[audio footwear]).order(:id).pluck(:id)

    assert_equal [1, 2], distinct_ids
    assert_equal [1, 2], not_ids
    assert_equal [3], in_ids
  end

  def test_complex_or_and_subquery_filters_execute
    left = Product.where(price: 0..50).search(:description).matching_all("budget")
    right = Product.where(rating: 4..).search(:description).matching_all("premium")
    assert_equal [4], left.or(right).order(:id).pluck(:id)

    avg_footwear = Product.where(category: "footwear").select("AVG(price)")
    subquery_ids = Product.search(:description).matching_all("running")
                         .where("price < (?)", avg_footwear)
                         .order(:id)
                         .pluck(:id)
    assert_equal [2, 6], subquery_ids
  end

  def test_relation_mutators_unscope_rewhere_readonly_execute
    unscoped_ids = Product.where(in_stock: true)
                          .order(rating: :desc)
                          .search(:description)
                          .matching_all("shoes")
                          .unscope(:order)
                          .order(:id)
                          .pluck(:id)
    assert_equal [1, 2], unscoped_ids

    rewhere_ids = Product.where(in_stock: true)
                         .search(:description)
                         .matching_all("shoes")
                         .rewhere(in_stock: false)
                         .pluck(:id)
    assert_empty rewhere_ids

    readonly_rows = Product.search(:description).matching_all("shoes").readonly.limit(1).to_a
    assert_equal true, readonly_rows.first.readonly?
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
    conn.execute("TRUNCATE TABLE categories RESTART IDENTITY;")

    Product.create!(description: "running shoes lightweight", category: "footwear", rating: 5, in_stock: true, price: 120)
    Product.create!(description: "trail running shoes grip", category: "footwear", rating: 4, in_stock: true, price: 90)
    Product.create!(description: "wireless bluetooth earbuds", category: "audio", rating: 5, in_stock: true, price: 80)
    Product.create!(description: "budget wired earbuds", category: "audio", rating: 3, in_stock: false, price: 20)
    Product.create!(description: "hiking boots waterproof", category: "footwear", rating: 4, in_stock: true, price: 110)
    Product.create!(description: "running socks breathable", category: "apparel", rating: 2, in_stock: true, price: 15)

    Category.create!(name: "footwear")
    Category.create!(name: "audio")
    Category.create!(name: "apparel")
    Category.create!(name: "home")
  end
end
