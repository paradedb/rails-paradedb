# frozen_string_literal: true

require "spec_helper"

class BehaviorProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

class BehaviorCategory < ActiveRecord::Base
  self.table_name = :categories
end

RSpec.describe "UserApiBehaviorIntegrationTest" do
  before do
    skip "Behavior integration tests require PostgreSQL" unless postgresql?

    ensure_paradedb_setup!
    seed_products!
  end
  it "matching all executes and returns rows" do
    ids = BehaviorProduct.search(:description)
                         .matching_all("running", "shoes")
                         .order(:id)
                         .pluck(:id)

    assert_equal [1, 2], ids
  end
  it "matching any executes and returns rows" do
    ids = BehaviorProduct.search(:description)
                         .matching_any("wireless", "hiking")
                         .order(:id)
                         .pluck(:id)

    assert_equal [3, 5], ids
  end
  it "matching with tokenizer override executes" do
    ids = BehaviorProduct.search(:description)
                         .matching_any("running shoes", tokenizer: "whitespace")
                         .order(:id)
                         .pluck(:id)

    assert_equal [1, 2, 6], ids
  end
  it "matching with tokenizer + fuzzy distance defers error to database" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      BehaviorProduct.search(:description)
                     .matching_any("runing shose", tokenizer: "whitespace", distance: 1)
                     .order(:id)
                     .pluck(:id)
    end
    assert_match(/cannot cast type/i, error.message)
  end
  it "matching with tokenizer + fuzzy constant score defers error to database" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      BehaviorProduct.search(:description)
                     .matching_any("runing shose", tokenizer: "whitespace", distance: 1, constant_score: 1.0)
                     .order(:id)
                     .pluck(:id)
    end
    assert_match(/cannot cast type/i, error.message)
  end
  it "phrase near and phrase prefix execute" do
    phrase_ids = BehaviorProduct.search(:description).phrase("running shoes").order(:id).pluck(:id)
    near_ids = BehaviorProduct.search(:description).near("running", "shoes", distance: 1).order(:id).pluck(:id)
    prefix_ids = BehaviorProduct.search(:category).phrase_prefix("foot").order(:id).pluck(:id)
    prefix_max_ids = BehaviorProduct.search(:category).phrase_prefix("foot", max_expansion: 100).order(:id).pluck(:id)

    assert_equal [1, 2], phrase_ids
    assert_equal [1, 2], near_ids
    assert_equal [1, 2, 5], prefix_ids
    assert_equal prefix_ids, prefix_max_ids
  end
  it "parse, match all, and exists wrappers execute" do
    parse_ids = BehaviorProduct.search(:description)
                               .parse("running AND shoes", lenient: true)
                               .order(:id)
                               .pluck(:id)
    parse_default_ids = BehaviorProduct.search(:description)
                                       .parse("running shoes")
                                       .order(:id)
                                       .pluck(:id)
    parse_conj_ids = BehaviorProduct.search(:description)
                                    .parse("running shoes", conjunction_mode: true)
                                    .order(:id)
                                    .pluck(:id)
    all_ids = BehaviorProduct.search(:id).match_all.order(:id).limit(3).pluck(:id)
    exists_ids = BehaviorProduct.search(:id).exists.order(:id).limit(3).pluck(:id)

    assert_equal [1, 2], parse_ids
    assert_equal [1, 2], parse_conj_ids
    assert_operator parse_default_ids.length, :>, parse_conj_ids.length
    assert_equal [1, 2, 3], all_ids
    assert_equal [1, 2, 3], exists_ids
  end
  it "range wrapper executes for numeric field" do
    inclusive_ids = BehaviorProduct.search(:rating).range(4..5).order(:id).pluck(:id)
    half_open_ids = BehaviorProduct.search(:rating).range(gte: 4, lt: 5).order(:id).pluck(:id)

    assert_equal [1, 2, 3, 5], inclusive_ids
    assert_equal [2, 5], half_open_ids
  end
  it "term regex and fuzzy execute" do
    term_ids = BehaviorProduct.search(:category).term("audio").order(:id).pluck(:id)
    term_set_ids = BehaviorProduct.search(:category).term_set(%w[audio footwear]).order(:id).pluck(:id)
    regex_ids = BehaviorProduct.search(:description).regex("run.*").order(:id).pluck(:id)
    fuzzy_ids = BehaviorProduct.search(:description).term("shose", distance: 2).order(:id).pluck(:id)

    assert_equal [3, 4], term_ids
    assert_equal [1, 2, 3, 4, 5], term_set_ids
    assert_equal [1, 2, 6], regex_ids
    assert_equal [1, 2], fuzzy_ids
  end
  it "fuzzy with constant score executes" do
    baseline_ids = BehaviorProduct.search(:description)
                                  .term("shose", distance: 2)
                                  .order(:id)
                                  .pluck(:id)

    const_ids = BehaviorProduct.search(:description)
                               .term("shose", distance: 2, constant_score: 1.0)
                               .order(:id)
                               .pluck(:id)

    assert_equal baseline_ids, const_ids
  end
  it "phrase slop with constant score executes" do
    baseline_ids = BehaviorProduct.search(:description)
                                  .phrase("running shoes", slop: 2)
                                  .order(:id)
                                  .pluck(:id)

    const_ids = BehaviorProduct.search(:description)
                               .phrase("running shoes", slop: 2, constant_score: 1.0)
                               .order(:id)
                               .pluck(:id)

    assert_equal baseline_ids, const_ids
  end
  it "more like this with id executes and returns similar rows" do
    ids = BehaviorProduct.more_like_this(3, fields: [:description]).limit(5).pluck(:id)

    assert_includes ids, 4
  end
  it "more like this with json single field executes" do
    json_doc = { description: "running shoes" }.to_json
    ids = BehaviorProduct.more_like_this(json_doc).order(:id).pluck(:id)

    assert_includes ids, 1
    assert_includes ids, 2
  end
  it "more like this with json multiple fields executes" do
    json_doc = { description: "running shoes", category: "footwear" }.to_json
    ids = BehaviorProduct.more_like_this(json_doc).order(:id).pluck(:id)

    assert_includes ids, 1
    assert_includes ids, 2
  end
  it "more like this with json category only executes" do
    json_doc = { category: "audio" }.to_json
    ids = BehaviorProduct.more_like_this(json_doc).order(:id).pluck(:id)

    assert_includes ids, 3
    assert_includes ids, 4
  end
  it "more like this with json combined with filters executes" do
    json_doc = { description: "running" }.to_json
    ids = BehaviorProduct.more_like_this(json_doc)
                          .where(in_stock: true)
                          .where("rating >= ?", 4)
                          .order(:id)
                          .pluck(:id)

    assert_includes ids, 1
    assert_includes ids, 2
  end
  it "with score and with snippet materialize columns" do
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
  it "with snippets materialize array column with rails-style options" do
    rows = BehaviorProduct.search(:description)
                          .matching_all("running")
                          .with_snippets(
                            :description,
                            start_tag: "<em>",
                            end_tag: "</em>",
                            max_chars: 15,
                            limit: 1,
                            offset: 0,
                            sort_by: :position
                          )
                          .order(:id)
                          .limit(2)
                          .to_a

    refute_empty rows
    rows.each do |row|
      refute_nil row.description_snippets
      assert_kind_of Array, row.description_snippets
      refute_empty row.description_snippets
    end
  end
  it "with snippet positions materialize offsets column" do
    rows = BehaviorProduct.search(:description)
                          .matching_all("running")
                          .with_snippet_positions(:description)
                          .order(:id)
                          .limit(2)
                          .to_a

    refute_empty rows
    rows.each do |row|
      refute_nil row.description_snippet_positions
      assert_kind_of Array, row.description_snippet_positions
      refute_empty row.description_snippet_positions
    end
  end
  it "facets and with facets execute and parse results" do
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
  it "with facets exact false executes" do
    rel = BehaviorProduct.search(:description)
                         .matching_all("running shoes")
                         .with_facets(:rating, size: 10, exact: false)
                         .order(:id)
                         .limit(10)

    rows = rel.to_a
    assert_equal [1, 2], rows.map(&:id)

    rel_facets = rel.facets
    assert_kind_of Hash, rel_facets
    assert_includes rel_facets, "rating"
  end
  it "with facets without top-k shape raises friendly error" do
    rel = BehaviorProduct.search(:description).matching_all("running shoes").with_facets(:rating, size: 10)
    error = assert_raises(ParadeDB::FacetQueryError) { rel.to_a }
    assert_includes error.message, "ORDER BY and LIMIT"
  end
  it "facets with standard where binds executes" do
    facets = BehaviorProduct.where(in_stock: true)
                            .extending(ParadeDB::SearchMethods)
                            .facets(:rating)

    assert_kind_of Hash, facets
    assert_includes facets, "rating"
  end
  it "matching all with filters matches raw sql" do
    raw_sql = <<~SQL
      SELECT id
      FROM products
      WHERE description &&& 'running shoes'
        AND price <= 120
      ORDER BY rating DESC, id ASC
      LIMIT 2
    SQL

    relation = BehaviorProduct.search(:description)
                              .matching_all("running", "shoes")
                              .where("price <= ?", 120)
                              .order(rating: :desc, id: :asc)
                              .limit(2)

    assert_ids_match_sql(raw_sql, relation)
  end
  it "search with join matches raw sql" do
    raw_sql = <<~SQL
      SELECT products.id
      FROM products
      INNER JOIN categories ON categories.name = products.category
      WHERE products.description &&& 'running'
        AND categories.name = 'footwear'
      ORDER BY products.id
    SQL

    relation = BehaviorProduct.joins("INNER JOIN categories ON categories.name = products.category")
                              .search(:description)
                              .matching_all("running")
                              .where(categories: { name: "footwear" })
                              .order(:id)

    assert_ids_match_sql(raw_sql, relation)
  end
  it "search with or scope matches raw sql" do
    raw_sql = <<~SQL
      SELECT id
      FROM products
      WHERE (in_stock = TRUE AND description &&& 'earbuds')
        OR (rating >= 4 AND description &&& 'boots')
      ORDER BY id
    SQL

    left = BehaviorProduct.where(in_stock: true)
                          .search(:description)
                          .matching_all("earbuds")
    right = BehaviorProduct.where("rating >= ?", 4)
                           .search(:description)
                           .matching_all("boots")

    relation = left.or(right).order(:id)

    assert_ids_match_sql(raw_sql, relation)
  end
  it "search with group and having matches raw sql" do
    raw_sql = <<~SQL
      SELECT category, COUNT(*)::int AS docs
      FROM products
      WHERE description &&& 'running'
      GROUP BY category
      HAVING COUNT(*) >= 2
      ORDER BY category
    SQL

    actual = BehaviorProduct.search(:description)
                            .matching_all("running")
                            .group(:category)
                            .having("COUNT(*) >= 2")
                            .order(:category)
                            .pluck(:category, Arel.sql("COUNT(*)::int"))

    assert_rows_match_sql(raw_sql, actual)
  end
  it "search with subquery filter matches raw sql" do
    raw_sql = <<~SQL
      SELECT id
      FROM products
      WHERE description &&& 'running'
        AND price < (SELECT AVG(price) FROM products WHERE category = 'footwear')
      ORDER BY id
    SQL

    avg_footwear = BehaviorProduct.where(category: "footwear").select("AVG(price)")

    relation = BehaviorProduct.search(:description)
                              .matching_all("running")
                              .where("price < (?)", avg_footwear)
                              .order(:id)

    assert_ids_match_sql(raw_sql, relation)
  end
  it "full text escape hatch matches raw sql" do
    raw_sql = <<~SQL
      SELECT id
      FROM products
      WHERE id @@@ pdb.all()
      ORDER BY id
      LIMIT 3
    SQL

    builder = ParadeDB::Arel::Builder.new(:products)
    predicate_sql = ParadeDB::Arel.to_sql(builder.full_text(:id, "pdb.all()"), BehaviorProduct.connection)
    relation = BehaviorProduct.where(Arel.sql(predicate_sql)).order(:id).limit(3)

    assert_ids_match_sql(raw_sql, relation)
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

    BehaviorProduct.create!(description: "running shoes lightweight", category: "footwear", rating: 5, in_stock: true, price: 120)
    BehaviorProduct.create!(description: "trail running shoes grip", category: "footwear", rating: 4, in_stock: true, price: 90)
    BehaviorProduct.create!(description: "wireless bluetooth earbuds", category: "audio", rating: 5, in_stock: true, price: 80)
    BehaviorProduct.create!(description: "budget wired earbuds", category: "audio", rating: 3, in_stock: false, price: 20)
    BehaviorProduct.create!(description: "hiking boots waterproof", category: "footwear", rating: 4, in_stock: true, price: 110)
    BehaviorProduct.create!(description: "running socks breathable", category: "apparel", rating: 2, in_stock: true, price: 15)

    BehaviorCategory.create!(name: "footwear")
    BehaviorCategory.create!(name: "audio")
    BehaviorCategory.create!(name: "apparel")
    BehaviorCategory.create!(name: "home")
  end

  def ids_from_sql(sql)
    ActiveRecord::Base.connection.exec_query(sql).rows.flatten.map(&:to_i)
  end

  def rows_from_sql(sql)
    ActiveRecord::Base.connection.exec_query(sql).rows
  end

  def assert_ids_match_sql(raw_sql, relation)
    assert_equal ids_from_sql(raw_sql), relation.pluck(:id)
  end

  def assert_rows_match_sql(raw_sql, rows)
    assert_equal rows_from_sql(raw_sql), rows
  end
end
