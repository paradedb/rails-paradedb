# frozen_string_literal: true

require "spec_helper"

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
end
