# frozen_string_literal: true

require "spec_helper"

# Model scoped to this test file to avoid class-name collisions
class ArelBehaviorProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

class ArelBehaviorCategory < ActiveRecord::Base
  self.table_name = :categories
end

# Integration tests that exercise Arel builder nodes against a real ParadeDB
# backend and verify actual row results from the seeded data.
#
# Seed data (6 rows):
#   1 | "running shoes lightweight"  | footwear | 5 | true  | 120
#   2 | "trail running shoes grip"   | footwear | 4 | true  |  90
#   3 | "wireless bluetooth earbuds" | audio    | 5 | true  |  80
#   4 | "budget wired earbuds"       | audio    | 3 | false |  20
#   5 | "hiking boots waterproof"    | footwear | 4 | true  | 110
#   6 | "running socks breathable"   | apparel  | 2 | true  |  15
RSpec.describe "ArelBehaviorIntegrationTest" do
  before do
    skip "Arel behavior integration tests require PostgreSQL" unless postgresql?

    ensure_paradedb_setup!
    seed_products!
  end

  # ---- match (matching_all) ----
  it "match returns expected rows" do
    ids = search(:description).matching_all("running", "shoes").order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end
  it "match single term broader results" do
    ids = search(:description).matching_all("running").order(:id).pluck(:id)
    assert_equal [1, 2, 6], ids
  end
  it "match with boost returns same rows" do
    # Boost affects scoring, not result set
    ids = search(:description).matching_all("running", "shoes", boost: 2).order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end

  # ---- match_any ----
  it "match any returns union" do
    ids = search(:description).matching_any("wireless", "hiking").order(:id).pluck(:id)
    assert_equal [3, 5], ids
  end
  it "match any single term" do
    ids = search(:description).matching_any("waterproof").order(:id).pluck(:id)
    assert_equal [5], ids
  end

  # ---- excluding ----
  it "excluding removes matching rows" do
    # "running" hits [1,2,6]; excluding "lightweight" removes 1
    ids = search(:description)
            .matching_all("running")
            .excluding("lightweight")
            .order(:id)
            .pluck(:id)
    assert_equal [2, 6], ids
  end
  it "excluding multiple terms" do
    ids = search(:description)
            .matching_all("earbuds")
            .excluding("budget")
            .order(:id)
            .pluck(:id)
    assert_equal [3], ids
  end

  # ---- phrase ----
  it "phrase without slop exact adjacency" do
    ids = search(:description).phrase("running shoes").order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end
  it "phrase with slop relaxes adjacency" do
    # "shoes lightweight" is in row 1 but not as exact phrase;
    # with slop it can still match "running shoes lightweight"
    ids = search(:description).phrase("running shoes", slop: 2).order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end
  it "phrase no match" do
    ids = search(:description).phrase("running earbuds").order(:id).pluck(:id)
    assert_empty ids
  end

  # ---- term ----
  it "term on category" do
    ids = search(:category).term("audio").order(:id).pluck(:id)
    assert_equal [3, 4], ids
  end
  it "term with boost returns same set" do
    ids = search(:category).term("audio", boost: 3).order(:id).pluck(:id)
    assert_equal [3, 4], ids
  end
  it "term on category footwear" do
    ids = search(:category).term("footwear").order(:id).pluck(:id)
    assert_equal [1, 2, 5], ids
  end

  # ---- fuzzy ----
  it "fuzzy corrects typo" do
    # "shose" is 1 edit from "shoes"
    ids = search(:description).fuzzy("shose", distance: 2).order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end
  it "fuzzy with prefix true" do
    ids = search(:description).fuzzy("runn", distance: 1, prefix: true).order(:id).pluck(:id)
    assert_includes ids, 1
    assert_includes ids, 2
  end
  it "fuzzy with small distance fewer matches" do
    # distance 1 may not correct "shose" -> "shoes" depending on tokenizer
    ids_d1 = search(:description).fuzzy("shose", distance: 1).order(:id).pluck(:id)
    ids_d2 = search(:description).fuzzy("shose", distance: 2).order(:id).pluck(:id)
    # Larger distance should be superset or equal
    assert (ids_d1 - ids_d2).empty?, "distance=2 should include all distance=1 results"
  end
  it "fuzzy with boost and prefix" do
    ids = search(:description)
            .fuzzy("runn", distance: 1, prefix: true, boost: 1.5)
            .order(:id)
            .pluck(:id)
    refute_empty ids
  end

  # ---- regex ----
  it "regex wildcard" do
    ids = search(:description).regex("run.*").order(:id).pluck(:id)
    assert_equal [1, 2, 6], ids
  end
  it "regex alternation" do
    ids = search(:description).regex("(wireless|hiking)").order(:id).pluck(:id)
    assert_equal [3, 5], ids
  end
  it "regex no match" do
    ids = search(:description).regex("zzznomatch.*").order(:id).pluck(:id)
    assert_empty ids
  end

  # ---- near ----
  it "near adjacent words" do
    ids = search(:description).near("running", "shoes", distance: 1).order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end
  it "near larger distance" do
    ids = search(:description).near("running", "shoes", distance: 5).order(:id).pluck(:id)
    # Same set — "running shoes" are always adjacent
    assert_equal [1, 2], ids
  end
  it "near no match" do
    ids = search(:description).near("running", "earbuds", distance: 1).order(:id).pluck(:id)
    assert_empty ids
  end

  # ---- phrase_prefix ----
  it "phrase prefix category" do
    ids = search(:category).phrase_prefix("foot").order(:id).pluck(:id)
    assert_equal [1, 2, 5], ids
  end
  it "phrase prefix description" do
    ids = search(:description).phrase_prefix("wire").order(:id).pluck(:id)
    assert_includes ids, 3
  end
  it "phrase prefix no match" do
    ids = search(:description).phrase_prefix("zzz").order(:id).pluck(:id)
    assert_empty ids
  end

  # ---- parse ----
  it "parse with and" do
    ids = search(:description).parse("running AND shoes", lenient: true).order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end
  it "parse with or" do
    ids = search(:description).parse("wireless OR hiking", lenient: true).order(:id).pluck(:id)
    assert_equal [3, 5], ids
  end
  it "parse without lenient" do
    ids = search(:description).parse("running AND shoes").order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end
  it "parse with lenient false" do
    ids = search(:description).parse("running AND shoes", lenient: false).order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end

  # ---- match_all ----
  it "match all returns all rows" do
    ids = search(:id).match_all.order(:id).pluck(:id)
    assert_equal [1, 2, 3, 4, 5, 6], ids
  end
  it "match all with limit" do
    ids = search(:id).match_all.order(:id).limit(3).pluck(:id)
    assert_equal [1, 2, 3], ids
  end

  # ---- more_like_this ----
  it "more like this with id" do
    ids = ArelBehaviorProduct.more_like_this(1, fields: [:description]).order(:id).pluck(:id)
    refute_empty ids
    # Should find row 2 (similar running shoes)
    assert_includes ids, 2
  end
  it "more like this with json string" do
    json_doc = { description: "wireless bluetooth" }.to_json
    ids = ArelBehaviorProduct.more_like_this(json_doc).order(:id).pluck(:id)
    assert_includes ids, 3
  end
  it "more like this with json multiple fields" do
    json_doc = { description: "running shoes", category: "footwear" }.to_json
    ids = ArelBehaviorProduct.more_like_this(json_doc).order(:id).pluck(:id)
    assert_includes ids, 1
    assert_includes ids, 2
  end
  it "more like this without fields" do
    ids = ArelBehaviorProduct.more_like_this(3).order(:id).pluck(:id)
    refute_empty ids
  end

  # ---- with_score ----
  it "with score returns positive floats" do
    rows = search(:description)
             .matching_all("running shoes")
             .with_score
             .order(:id)
             .to_a

    refute_empty rows
    rows.each do |row|
      score = row.search_score.to_f
      assert_operator score, :>, 0.0, "Score should be positive"
    end
  end
  it "with score ordering" do
    rows = search(:description)
             .matching_all("running", "shoes")
             .with_score
             .order(search_score: :desc)
             .to_a

    scores = rows.map { |r| r.search_score.to_f }
    assert_equal scores, scores.sort.reverse, "Rows should be ordered by descending score"
  end

  # ---- with_snippet ----
  it "with snippet default tags" do
    rows = search(:description)
             .matching_all("running shoes")
             .with_snippet(:description)
             .order(:id)
             .to_a

    refute_empty rows
    rows.each do |row|
      refute_nil row.description_snippet
      refute_empty row.description_snippet.to_s
    end
  end
  it "with snippet custom tags" do
    rows = search(:description)
             .matching_all("running shoes")
             .with_snippet(:description, start_tag: "<mark>", end_tag: "</mark>", max_chars: 100)
             .order(:id)
             .to_a

    refute_empty rows
    rows.each do |row|
      snippet = row.description_snippet.to_s
      refute_empty snippet
      assert_includes snippet, "<mark>"
      assert_includes snippet, "</mark>"
    end
  end
  it "with snippet and score together" do
    rows = search(:description)
             .matching_all("running shoes")
             .with_score
             .with_snippet(:description, start_tag: "<b>", end_tag: "</b>")
             .order(:id)
             .to_a

    refute_empty rows
    rows.each do |row|
      refute_nil row.search_score
      refute_nil row.description_snippet
      assert_includes row.description_snippet, "<b>"
    end
  end

  # ---- facets ----
  it "facets rating from search" do
    facets = search(:description).matching_all("running").facets(:rating)
    assert_kind_of Hash, facets
    assert_includes facets, "rating"
    # running matches rows 1 (rating 5), 2 (rating 4), 6 (rating 2)
    rating_json = facets["rating"].to_json
    assert_match(/[245]/, rating_json)
  end
  it "facets rating match all" do
    facets = search(:id).match_all.facets(:rating)
    assert_kind_of Hash, facets
    assert_includes facets, "rating"
  end
  it "facets returns parseable results" do
    facets = search(:id).match_all.facets(:rating, size: 10)
    assert_kind_of Hash, facets
    assert_includes facets, "rating"
    # Verify result is non-empty and JSON-serializable
    refute_empty facets["rating"].to_json
  end

  # ---- with_facets ----
  it "with facets returns rows and facets" do
    rel = search(:description)
            .matching_all("running", "shoes")
            .with_facets(:rating, size: 10)
            .order(:id)
            .limit(10)

    rows = rel.to_a
    assert_equal [1, 2], rows.map(&:id)

    f = rel.facets
    assert_kind_of Hash, f
    assert_includes f, "rating"
  end
  it "with facets with match all" do
    rel = search(:id)
            .match_all
            .with_facets(:rating, size: 10)
            .order(:id)
            .limit(10)

    f = rel.facets
    assert_kind_of Hash, f
    assert_includes f, "rating"
  end
  it "with facets requires order and limit" do
    rel = search(:description)
            .matching_all("running shoes")
            .with_facets(:category, size: 10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.to_a }
    assert_includes error.message, "ORDER BY and LIMIT"
  end

  # ---- Arel builder executed via where(Arel.sql(...)) ----
  it "arel builder match via where" do
    builder = ParadeDB::Arel::Builder.new(:products)
    predicate = builder.match(:description, "running", "shoes")
    predicate_sql = ParadeDB::Arel.to_sql(predicate, ArelBehaviorProduct.connection)

    ids = ArelBehaviorProduct.where(Arel.sql(predicate_sql)).order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end
  it "arel builder regex via where" do
    builder = ParadeDB::Arel::Builder.new(:products)
    predicate = builder.regex(:description, "run.*")
    predicate_sql = ParadeDB::Arel.to_sql(predicate, ArelBehaviorProduct.connection)

    ids = ArelBehaviorProduct.where(Arel.sql(predicate_sql)).order(:id).pluck(:id)
    assert_equal [1, 2, 6], ids
  end
  it "arel builder boolean composition via where" do
    builder = ParadeDB::Arel::Builder.new(:products)
    shoes = builder.match(:description, "shoes")
    cheap = builder.match(:description, "budget")
    predicate = shoes.and(cheap.not)
    predicate_sql = ParadeDB::Arel.to_sql(predicate, ArelBehaviorProduct.connection)

    ids = ArelBehaviorProduct.where(Arel.sql(predicate_sql)).order(:id).pluck(:id)
    assert_equal [1, 2], ids
  end
  it "arel builder or composition via where" do
    builder = ParadeDB::Arel::Builder.new(:products)
    wireless = builder.match(:description, "wireless")
    hiking = builder.match(:description, "hiking")
    predicate = wireless.or(hiking)
    predicate_sql = ParadeDB::Arel.to_sql(predicate, ArelBehaviorProduct.connection)

    ids = ArelBehaviorProduct.where(Arel.sql(predicate_sql)).order(:id).pluck(:id)
    assert_equal [3, 5], ids
  end
  it "arel builder results match search api" do
    # Verify Arel builder produces identical results to the high-level API
    api_ids = search(:description).matching_all("running", "shoes").order(:id).pluck(:id)

    builder = ParadeDB::Arel::Builder.new(:products)
    predicate = builder.match(:description, "running shoes")
    predicate_sql = ParadeDB::Arel.to_sql(predicate, ArelBehaviorProduct.connection)
    arel_ids = ArelBehaviorProduct.where(Arel.sql(predicate_sql)).order(:id).pluck(:id)

    assert_equal api_ids, arel_ids
  end

  # ---- Complex real-world patterns ----
  it "search with where filter" do
    ids = search(:description)
            .matching_all("running")
            .where(in_stock: true)
            .where("price <= ?", 100)
            .order(:id)
            .pluck(:id)

    # Row 1 is $120 (excluded), row 2 is $90 (included), row 6 is $15 (included)
    assert_equal [2, 6], ids
  end
  it "search or composition" do
    left = ArelBehaviorProduct.where(in_stock: true)
                              .search(:description)
                              .matching_all("earbuds")
    right = ArelBehaviorProduct.where("rating >= ?", 4)
                               .search(:description)
                               .matching_all("boots")

    ids = left.or(right).order(:id).pluck(:id)
    # left: earbuds + in_stock -> row 3
    # right: boots + rating >= 4 -> row 5
    assert_equal [3, 5], ids
  end
  it "search with limit and offset" do
    ids = search(:id).match_all.order(:id).limit(2).offset(2).pluck(:id)
    assert_equal [3, 4], ids
  end
  it "chained search fields" do
    ids = search(:description).matching_all("running")
            .search(:category).term("footwear")
            .order(:id)
            .pluck(:id)
    # running => [1,2,6], footwear => [1,2,5] => intersection [1,2]
    assert_equal [1, 2], ids
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end

  def search(column)
    ArelBehaviorProduct.search(column)
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

    ArelBehaviorProduct.create!(description: "running shoes lightweight", category: "footwear", rating: 5, in_stock: true, price: 120)
    ArelBehaviorProduct.create!(description: "trail running shoes grip", category: "footwear", rating: 4, in_stock: true, price: 90)
    ArelBehaviorProduct.create!(description: "wireless bluetooth earbuds", category: "audio", rating: 5, in_stock: true, price: 80)
    ArelBehaviorProduct.create!(description: "budget wired earbuds", category: "audio", rating: 3, in_stock: false, price: 20)
    ArelBehaviorProduct.create!(description: "hiking boots waterproof", category: "footwear", rating: 4, in_stock: true, price: 110)
    ArelBehaviorProduct.create!(description: "running socks breathable", category: "apparel", rating: 2, in_stock: true, price: 15)

    ArelBehaviorCategory.create!(name: "footwear")
    ArelBehaviorCategory.create!(name: "audio")
    ArelBehaviorCategory.create!(name: "apparel")
    ArelBehaviorCategory.create!(name: "home")
  end
end
