# frozen_string_literal: true

require "spec_helper"

class UnitProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_paradedb_index = true
end

class UnitCategory < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :categories
  self.has_paradedb_index = true
end

class UserApiUnitTest < Minitest::Test
  def test_matching_all_and_filters
    sql = UnitProduct.search(:description)
                     .matching_all("running", "shoes")
                     .where(in_stock: true)
                     .to_sql

    assert_sql_equal %(SELECT products.* FROM products
      WHERE ("products"."description" &&& 'running shoes') AND "products"."in_stock" = TRUE), sql
  end

  def test_matching_any
    sql = UnitProduct.search(:description).matching_any("wireless", "bluetooth").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ||| 'wireless bluetooth')), sql
  end

  def test_phrase_slop
    sql = UnitProduct.search(:description).phrase("running shoes", slop: 2).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ### 'running shoes'::pdb.slop(2))), sql
  end

  def test_fuzzy_prefix_boost
    sql = UnitProduct.search(:description).fuzzy("shose", distance: 2, prefix: false, boost: 2).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(2))), sql
  end

  def test_term_exact
    sql = UnitProduct.search(:description).term("literal").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" === 'literal')), sql
  end

  def test_regex
    sql = UnitProduct.search(:description).regex("run.*").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.regex('run.*'))), sql
  end

  def test_near
    sql = UnitProduct.search(:description).near("sleek", "shoes", distance: 1).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## 'shoes'))), sql
  end

  def test_phrase_prefix
    sql = UnitProduct.search(:description).phrase_prefix("run", "sh").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh']))), sql
  end

  def test_parse_query_with_lenient
    sql = UnitProduct.search(:description).parse("running AND shoes", lenient: true).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes', lenient => true))), sql
  end

  def test_parse_query_without_options
    sql = UnitProduct.search(:description).parse("running AND shoes").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes'))), sql
  end

  def test_parse_query_with_lenient_false
    sql = UnitProduct.search(:description).parse("running AND shoes", lenient: false).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes', lenient => false))), sql
  end

  def test_match_all_wrapper
    sql = UnitProduct.search(:id).match_all.to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.all())), sql
  end

  def test_more_like_this
    sql = UnitProduct.more_like_this(5, fields: [:description]).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this(5, ARRAY['description']))), sql
  end

  def test_excluding
    sql = UnitProduct.search(:description).matching_all("shoes").excluding("cheap").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes') AND (NOT ("products"."description" &&& 'cheap'))), sql
  end

  def test_or_composition
    base = UnitProduct.where(in_stock: true).order(id: :desc).limit(10)
    left = base.search(:description).matching_all("shoes")
    right = base.search(:category).matching_all("footwear")
    sql = left.or(right).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE "products"."in_stock" = TRUE AND ("products"."description" &&& 'shoes' OR "products"."category" &&& 'footwear') ORDER BY "products"."id" DESC LIMIT 10), sql
  end

  def test_with_score
    sql = UnitProduct.search(:description).matching_all("shoes").with_score.to_sql
    assert_sql_equal %(SELECT products.*, pdb.score("products"."id") AS search_score FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end

  def test_with_snippet_default
    sql = UnitProduct.search(:description).matching_all("shoes").with_snippet(:description).to_sql
    assert_sql_equal %(SELECT products.*, pdb.snippet("products"."description") AS description_snippet FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end

  def test_with_snippet_custom
    sql = UnitProduct.search(:description).matching_all("shoes").with_snippet(:description, start_tag: "<b>", end_tag: "</b>", max_chars: 50).to_sql
    assert_sql_equal %(SELECT products.*, pdb.snippet("products"."description", '<b>', '</b>', 50) AS description_snippet FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end

  def test_with_score_then_with_snippet_keeps_both_projections
    sql = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_score
                     .with_snippet(:description)
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.score("products"."id") AS search_score, pdb.snippet("products"."description") AS description_snippet FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end

  def test_with_snippet_then_with_score_keeps_both_projections
    sql = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_snippet(:description)
                     .with_score
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.snippet("products"."description") AS description_snippet, pdb.score("products"."id") AS search_score FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end

  def test_facets_only
    facet_sql = UnitProduct.search(:description).matching_all("shoes")
                           .build_facet_query(fields: [:category, :brand], size: 10, order: "-count")
                           .sql

    expected = <<~SQL.strip
      SELECT
        pdb.agg('{"terms": {"field": "category", "size": 10, "order": {"_count": "desc"}}}') AS category_facet,
        pdb.agg('{"terms": {"field": "brand", "size": 10, "order": {"_count": "desc"}}}') AS brand_facet
      FROM products
      WHERE ("products"."description" &&& 'shoes')
    SQL

    assert_sql_equal expected, facet_sql
  end

  def test_facets_without_paradedb_predicates
    facet_sql = UnitProduct.where(in_stock: true)
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    expected = <<~SQL.strip
      SELECT
        pdb.agg('{"terms": {"field": "category", "size": 10}}') AS category_facet
      FROM products
      WHERE "products"."in_stock" = TRUE AND "products"."id" @@@ pdb.all()
    SQL

    assert_sql_equal expected, facet_sql
  end

  def test_facets_with_no_predicates
    facet_sql = UnitProduct.all
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 5, order: nil)
                           .sql

    expected = <<~SQL.strip
      SELECT
        pdb.agg('{"terms": {"field": "category", "size": 5}}') AS category_facet
      FROM products
      WHERE "products"."id" @@@ pdb.all()
    SQL

    assert_sql_equal expected, facet_sql
  end

  def test_with_facets_without_paradedb_predicates
    sql = UnitProduct.where(in_stock: true)
                     .extending(ParadeDB::SearchMethods)
                     .with_facets(:category, size: 10)
                     .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.agg('{"terms": {"field": "category", "size": 10}}') OVER () AS _category_facet FROM products
      WHERE "products"."in_stock" = TRUE AND ("products"."id" @@@ pdb.all())
    SQL

    assert_sql_equal expected, sql
  end

  def test_with_facets_load_requires_order_and_limit
    rel = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY and LIMIT"
  end

  def test_with_facets_load_requires_limit
    rel = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)
                     .order(:id)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "LIMIT"
  end

  def test_with_facets_load_requires_order
    rel = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)
                     .limit(10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY"
  end

  def test_search_on_relation_preserves_where
    # Verify .search() works on relations and preserves WHERE clauses
    sql = UnitProduct.where(in_stock: true)
                     .search(:description)
                     .matching_all("shoes")
                     .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."in_stock" = TRUE AND ("products"."description" &&& 'shoes')
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_on_relation_preserves_order_and_limit
    # Verify .search() preserves ORDER BY and LIMIT
    sql = UnitProduct.where(price: 0..100)
                     .order(rating: :desc)
                     .limit(10)
                     .search(:description)
                     .matching_all("wireless")
                     .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."price" BETWEEN 0 AND 100 AND ("products"."description" &&& 'wireless')
      ORDER BY "products"."rating" DESC
      LIMIT 10
    SQL

    assert_sql_equal expected, sql
  end
end
