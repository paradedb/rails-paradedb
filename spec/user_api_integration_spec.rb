# frozen_string_literal: true

require "spec_helper"

class Product < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_parade_db_index = true
end

class Category < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :categories
  self.has_parade_db_index = true
end

class UserApiIntegrationTest < Minitest::Test
  def test_matching_with_filters
    sql = Product.search(:description)
                 .matching("running", "shoes")
                 .where(in_stock: true)
                 .where("products.price < 100")
                 .where(rating: 4..)
                 .to_sql

    expected = <<~SQL.strip
      SELECT * FROM products
      WHERE "products"."description" &&& 'running shoes'
        AND "products"."in_stock" = true
        AND products.price < 100
        AND "products"."rating" >= 4
    SQL

    assert_equal expected, sql
  end

  def test_chain_multiple_search_fields_and
    sql = Product.search(:description).matching("running", "shoes")
                 .search(:category).phrase("Footwear")
                 .to_sql

    expected = <<~SQL.strip
      SELECT * FROM products
      WHERE ("products"."description" &&& 'running shoes' AND "products"."category" ### 'Footwear')
    SQL

    assert_equal expected, sql
  end

  def test_match_any_or_semantics
    sql = Product.search(:description).matching(any: ["wireless", "bluetooth"]).to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" ||| 'wireless bluetooth'), sql
  end

  def test_excluding_terms
    sql = Product.search(:description)
                 .matching("shoes")
                 .excluding("cheap", "budget")
                 .to_sql

    expected = <<~SQL.strip
      SELECT * FROM products
      WHERE ("products"."description" &&& 'shoes' AND NOT ("products"."description" &&& 'cheap budget'))
    SQL

    assert_equal expected, sql
  end

  def test_phrase_with_slop
    sql = Product.search(:description).phrase("running shoes", slop: 2).to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" ### 'running shoes'::pdb.slop(2)), sql
  end

  def test_fuzzy_with_prefix
    sql = Product.search(:description).fuzzy("runn", distance: 1, prefix: true).to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" === 'runn'::pdb.fuzzy(1, "true")), sql
  end

  def test_regex
    sql = Product.search(:description).regex("run.*shoes").to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" @@@ pdb.regex('run.*shoes')), sql
  end

  def test_term_exact
    sql = Product.search(:description).term("shoes").to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" === 'shoes'), sql
  end

  def test_near_proximity
    sql = Product.search(:description).near("sleek", "shoes", distance: 1).to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" @@@ ('sleek' ## 1 ## 'shoes')), sql
  end

  def test_phrase_prefix
    sql = Product.search(:description).phrase_prefix("run", "sh").to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh'])), sql
  end

  def test_similar_to
    sql = Product.similar_to(3, fields: [:description]).to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."id" @@@ pdb.more_like_this(3, ARRAY['description'])), sql
  end

  def test_with_score_and_order
    sql = Product.search(:description)
                 .matching("running", "shoes")
                 .with_score
                 .order(search_score: :desc)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.score("products"."id") AS search_score FROM products
      WHERE "products"."description" &&& 'running shoes'
      ORDER BY search_score DESC
    SQL

    assert_equal expected, sql
  end

  def test_with_snippet_default
    sql = Product.search(:description)
                 .matching("running shoes")
                 .with_snippet(:description)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippet("products"."description") AS description_snippet FROM products
      WHERE "products"."description" &&& 'running shoes'
    SQL

    assert_equal expected, sql
  end

  def test_with_snippet_custom
    sql = Product.search(:description)
                 .matching("running shoes")
                 .with_snippet(:description, start_tag: '<mark>', end_tag: '</mark>', max_chars: 100)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippet("products"."description", '<mark>', '</mark>', 100) AS description_snippet FROM products
      WHERE "products"."description" &&& 'running shoes'
    SQL

    assert_equal expected, sql
  end

  def test_or_across_fields
    left = Product.search(:description).matching("shoes")
    right = Product.search(:category).matching("footwear")

    sql = left.or(right).to_sql

    expected = <<~SQL.strip
      SELECT * FROM products
      WHERE (("products"."description" &&& 'shoes') OR ("products"."category" &&& 'footwear'))
    SQL

    assert_equal expected, sql
  end

  def test_facets_only
    facet_sql = Product.search(:description).matching("shoes")
                       .facets(:category, :brand, size: 10, order: "-count")
                       .sql

    expected = <<~SQL.strip
      SELECT
        pdb.agg('{"terms": {"field": "category", "size": 10, "order": {"_count": "desc"}}}') AS category_facet,
        pdb.agg('{"terms": {"field": "brand", "size": 10, "order": {"_count": "desc"}}}') AS brand_facet
      FROM products
      WHERE "products"."description" &&& 'shoes'
    SQL

    assert_equal expected, facet_sql
  end

  def test_with_facets_rows_plus_facets
    sql = Product.search(:description).matching("shoes")
                 .where(in_stock: true)
                 .with_facets(:category, :brand, size: 10)
                 .order(rating: :desc)
                 .limit(10)
                 .to_sql

    expected = <<~SQL.strip
      SELECT *, pdb.agg('{"terms": {"field": "category", "size": 10}}') OVER () AS _category_facet, pdb.agg('{"terms": {"field": "brand", "size": 10}}') OVER () AS _brand_facet FROM products
      WHERE "products"."description" &&& 'shoes' AND "products"."in_stock" = true
      ORDER BY rating DESC
      LIMIT 10
    SQL

    assert_equal expected, sql
  end
end
