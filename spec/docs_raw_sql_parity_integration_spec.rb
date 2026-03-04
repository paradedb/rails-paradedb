# frozen_string_literal: true

require "spec_helper"
require "json"

class DocsParityProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

RSpec.describe "DocsRawSqlParityIntegrationTest" do
  before do
    skip "Docs parity integration tests require PostgreSQL" unless postgresql?

    ensure_paradedb_setup!
    seed_products!
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
    actual = DocsParityProduct.search(:category)
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

  it "filtered facets_agg matches raw SQL FILTER (WHERE) counts" do
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

    actual = DocsParityProduct.facets_agg(
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

  it "query regex helper matches raw pdb.regex json" do
    expected = parse_json_value(ActiveRecord::Base.connection.select_value("SELECT pdb.regex('key.*')"))
    actual = ParadeDB::Query.regex("key.*")

    assert_equal expected, actual
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
    actual = DocsParityProduct.search(:id)
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

    DocsParityProduct.create!(description: "running shoes lightweight", category: "footwear", rating: 5, in_stock: true, price: 120)
    DocsParityProduct.create!(description: "trail running shoes grip", category: "footwear", rating: 4, in_stock: true, price: 90)
    DocsParityProduct.create!(description: "wireless bluetooth earbuds", category: "electronics", rating: 5, in_stock: true, price: 80)
    DocsParityProduct.create!(description: "budget wired earbuds", category: "electronics", rating: 3, in_stock: false, price: 20)
    DocsParityProduct.create!(description: "gaming keyboard", category: "electronics", rating: 4, in_stock: true, price: 110)
    DocsParityProduct.create!(description: "running socks breathable", category: "apparel", rating: 2, in_stock: true, price: 15)
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
