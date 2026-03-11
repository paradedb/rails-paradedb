# frozen_string_literal: true

require "spec_helper"
require "json"

class MltFacetProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

RSpec.describe "MltAndFacetsIntegrationTest" do
  before do
    skip "MLT/facets integration tests require PostgreSQL" unless postgresql?

    ensure_paradedb_setup!
    seed_products!
  end
  it "more like this with min term frequency filters all terms" do
    ids = MltFacetProduct.more_like_this(
      @earbuds_id,
      fields: [:description],
      min_term_freq: 2
    ).order(:id).pluck(:id)

    assert_equal [], ids
  end
  it "more like this with stopwords executes" do
    ids = MltFacetProduct.more_like_this(
      @earbuds_id,
      fields: [:description],
      stopwords: %w[wireless earbuds]
    ).order(:id).pluck(:id)

    assert_kind_of Array, ids
  end
  it "facets with custom agg returns single payload" do
    facets = MltFacetProduct.search(:description)
                            .matching_all("running")
                            .facets(agg: { "value_count" => { "field" => "id" } })

    assert_kind_of Hash, facets
    assert_includes facets, "agg"
    assert_operator facets["agg"]["value"].to_f, :>=, 1.0
  end
  it "with facets with custom agg returns rows and facets" do
    relation = MltFacetProduct.search(:description)
                             .matching_all("running")
                             .with_facets(agg: { "value_count" => { "field" => "id" } })
                             .order(:id)
                             .limit(10)

    rows = relation.to_a
    refute_empty rows

    facets = relation.facets
    assert_kind_of Hash, facets
    assert_includes facets, "agg"
    assert_operator facets["agg"]["value"].to_f, :>=, rows.length.to_f
  end
  it "with facets custom agg adds match all for non paradedb filters" do
    relation = MltFacetProduct.where(in_stock: true)
                             .extending(ParadeDB::SearchMethods)
                             .with_facets(agg: { "value_count" => { "field" => "id" } })
                             .order(:id)
                             .limit(10)

    sql = relation.to_sql
    assert_includes sql, %("products"."id" @@@ pdb.all())

    facets = relation.facets
    assert_includes facets, "agg"
    assert_operator facets["agg"]["value"].to_f, :>=, 1.0
  end
  it "facets_agg helper returns named aggregations" do
    rel = MltFacetProduct.search(:description).matching_all("running")
    aggs = rel.facets_agg(
      docs: ParadeDB::Aggregations.value_count(:id),
      avg_rating: ParadeDB::Aggregations.avg(:rating),
      rating_hist: ParadeDB::Aggregations.histogram(:rating, interval: 1)
    )

    assert_kind_of Hash, aggs
    assert_includes aggs, "docs"
    assert_includes aggs, "avg_rating"
    assert_includes aggs, "rating_hist"
  end
  it "with_agg helper returns rows and named aggregations" do
    rel = MltFacetProduct.search(:description)
                        .matching_all("running")
                        .with_agg(
                          docs: ParadeDB::Aggregations.value_count(:id),
                          by_rating: ParadeDB::Aggregations.range(
                            :rating,
                            ranges: [{ to: 3 }, { from: 3, to: 5 }, { from: 5 }]
                          )
                        )
                        .order(:id)
                        .limit(10)

    rows = rel.to_a
    refute_empty rows

    aggs = rel.aggregates
    assert_kind_of Hash, aggs
    assert_includes aggs, "docs"
    assert_includes aggs, "by_rating"
  end
  context "docs parity aggregations" do
    before do
      seed_docs_parity_products!
    end

    it "aggregate_by grouped value_count matches raw SQL" do
      raw_sql = <<~SQL
        SELECT rating, pdb.agg('{"value_count": {"field": "id"}}') AS agg
        FROM products
        WHERE category === 'electronics'
        GROUP BY rating
        ORDER BY rating
        LIMIT 5
      SQL

      expected = normalized_grouped_rows(raw_sql)
      actual = MltFacetProduct.search(:category)
                              .term("electronics")
                              .aggregate_by(
                                :rating,
                                agg: ParadeDB::Aggregations.value_count(:id)
                              )
                              .order(:rating)
                              .limit(5)
                              .map { |row| [row.rating, parse_json_value(row.attributes["agg"])] }

      assert_equal expected, actual
    end

    it "filtered facets_agg matches raw SQL FILTER counts" do
      raw_sql = <<~SQL
        SELECT
            pdb.agg('{"value_count": {"field": "id"}}')
            FILTER (WHERE category === 'electronics') AS electronics_count,
            pdb.agg('{"value_count": {"field": "id"}}')
            FILTER (WHERE category === 'footwear') AS footwear_count
        FROM products
      SQL

      expected_row = ActiveRecord::Base.connection.exec_query(raw_sql).first
      expected_electronics = parse_json_value(expected_row["electronics_count"])
      expected_footwear = parse_json_value(expected_row["footwear_count"])

      actual = MltFacetProduct.facets_agg(
        electronics_count: ParadeDB::Aggregations.filtered(
          ParadeDB::Aggregations.value_count(:id),
          field: :category,
          term: "electronics"
        ),
        footwear_count: ParadeDB::Aggregations.filtered(
          ParadeDB::Aggregations.value_count(:id),
          field: :category,
          term: "footwear"
        )
      )

      assert_equal expected_electronics, actual["electronics_count"]
      assert_equal expected_footwear, actual["footwear_count"]
    end

    it "top_hits aggregate_by matches raw SQL" do
      raw_sql = <<~SQL
        SELECT pdb.agg('{"top_hits": {"size": 3, "sort": [{"price": "desc"}], "docvalue_fields": ["id", "price"]}}') AS agg
        FROM products
        WHERE id @@@ pdb.all()
        GROUP BY rating
        ORDER BY rating
      SQL

      expected = normalized_single_agg_rows(raw_sql)
      actual = MltFacetProduct.search(:id)
                              .match_all
                              .aggregate_by(
                                :rating,
                                agg: ParadeDB::Aggregations.top_hits(
                                  size: 3,
                                  sort: [{ price: "desc" }],
                                  docvalue_fields: %w[id price]
                                )
                              )
                              .order(:rating)
                              .map { |row| parse_json_value(row.attributes["agg"]) }

      assert_equal expected, actual
    end
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
    MltFacetProduct.connection.execute("TRUNCATE TABLE products RESTART IDENTITY;")

    MltFacetProduct.create!(description: "running shoes lightweight", category: "footwear", rating: 5, in_stock: true, price: 120)
    MltFacetProduct.create!(description: "trail running shoes grip", category: "footwear", rating: 4, in_stock: true, price: 90)
    @earbuds_id = MltFacetProduct.create!(description: "wireless bluetooth earbuds", category: "audio", rating: 5, in_stock: true, price: 80).id
    MltFacetProduct.create!(description: "budget wired earbuds", category: "audio", rating: 3, in_stock: false, price: 20)
    MltFacetProduct.create!(description: "hiking boots waterproof", category: "footwear", rating: 4, in_stock: true, price: 110)
    MltFacetProduct.create!(description: "running socks breathable", category: "apparel", rating: 2, in_stock: true, price: 15)
  end

  def seed_docs_parity_products!
    MltFacetProduct.connection.execute("TRUNCATE TABLE products RESTART IDENTITY;")

    MltFacetProduct.create!(description: "sleek running shoes", category: "footwear", rating: 5, in_stock: true, price: 120)
    MltFacetProduct.create!(description: "running sleek shoes", category: "footwear", rating: 4, in_stock: true, price: 90)
    MltFacetProduct.create!(description: "shoes running", category: "footwear", rating: 3, in_stock: true, price: 70)
    MltFacetProduct.create!(description: "white shoes", category: "footwear", rating: 4, in_stock: true, price: 95)
    MltFacetProduct.create!(description: "trail running shoes grip", category: "footwear", rating: 4, in_stock: true, price: 85)
    MltFacetProduct.create!(description: "wireless bluetooth earbuds", category: "electronics", rating: 5, in_stock: true, price: 80)
    MltFacetProduct.create!(description: "budget wired earbuds", category: "electronics", rating: 3, in_stock: false, price: 20)
    MltFacetProduct.create!(description: "gaming keyboard", category: "electronics", rating: 4, in_stock: true, price: 110)
    MltFacetProduct.create!(description: "running socks breathable", category: "apparel", rating: 2, in_stock: true, price: 15)
  end

  def parse_json_value(value)
    case value
    when nil
      nil
    when String
      JSON.parse(value)
    else
      value
    end
  end

  def normalized_grouped_rows(sql)
    ActiveRecord::Base.connection.exec_query(sql).rows.map do |row|
      [row[0], parse_json_value(row[1])]
    end
  end

  def normalized_single_agg_rows(sql)
    ActiveRecord::Base.connection.exec_query(sql).rows.map do |row|
      parse_json_value(row[0])
    end
  end
end
