# frozen_string_literal: true

require "spec_helper"

class UnitProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
  self.has_parade_db_index = true
end

class UnitCategory < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :categories
  self.has_parade_db_index = true
end

class UserApiUnitTest < Minitest::Test
  def test_matching_and_filters
    sql = UnitProduct.search(:description)
                     .matching("running", "shoes")
                     .where(in_stock: true)
                     .to_sql

    assert_equal %(SELECT * FROM products\nWHERE "products"."description" &&& 'running shoes' AND "products"."in_stock" = true), sql
  end

  def test_match_any
    sql = UnitProduct.search(:description).matching(any: %w[wireless bluetooth]).to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" ||| 'wireless bluetooth'), sql
  end

  def test_phrase_slop
    sql = UnitProduct.search(:description).phrase("running shoes", slop: 2).to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" ### 'running shoes'::pdb.slop(2)), sql
  end

  def test_fuzzy_prefix_boost
    sql = UnitProduct.search(:description).fuzzy("shose", distance: 2, prefix: false, boost: 2).to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(2)), sql
  end

  def test_term_exact
    sql = UnitProduct.search(:description).term("literal").to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" === 'literal'), sql
  end

  def test_regex
    sql = UnitProduct.search(:description).regex("run.*").to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" @@@ pdb.regex('run.*')), sql
  end

  def test_near
    sql = UnitProduct.search(:description).near("sleek", "shoes", distance: 1).to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" @@@ ('sleek' ## 1 ## 'shoes')), sql
  end

  def test_phrase_prefix
    sql = UnitProduct.search(:description).phrase_prefix("run", "sh").to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh'])), sql
  end

  def test_similar_to
    sql = UnitProduct.similar_to(5, fields: [:description]).to_sql
    assert_equal %(SELECT * FROM products\nWHERE "products"."id" @@@ pdb.more_like_this(5, ARRAY['description'])), sql
  end

  def test_excluding
    sql = UnitProduct.search(:description).matching("shoes").excluding("cheap").to_sql
    assert_equal %(SELECT * FROM products\nWHERE ("products"."description" &&& 'shoes' AND NOT ("products"."description" &&& 'cheap'))), sql
  end

  def test_or_composition
    left = UnitProduct.search(:description).matching("shoes")
    right = UnitProduct.search(:category).matching("footwear")
    sql = left.or(right).to_sql
    assert_equal %(SELECT * FROM products\nWHERE (("products"."description" &&& 'shoes') OR ("products"."category" &&& 'footwear'))), sql
  end

  def test_with_score
    sql = UnitProduct.search(:description).matching("shoes").with_score.to_sql
    assert_equal %(SELECT products.*, pdb.score("products"."id") AS search_score FROM products\nWHERE "products"."description" &&& 'shoes'), sql
  end

  def test_with_snippet_default
    sql = UnitProduct.search(:description).matching("shoes").with_snippet(:description).to_sql
    assert_equal %(SELECT products.*, pdb.snippet("products"."description") AS description_snippet FROM products\nWHERE "products"."description" &&& 'shoes'), sql
  end

  def test_with_snippet_custom
    sql = UnitProduct.search(:description).matching("shoes").with_snippet(:description, start_tag: "<b>", end_tag: "</b>", max_chars: 50).to_sql
    assert_equal %(SELECT products.*, pdb.snippet("products"."description", '<b>', '</b>', 50) AS description_snippet FROM products\nWHERE "products"."description" &&& 'shoes'), sql
  end

  def test_facets_only
    facet_sql = UnitProduct.search(:description).matching("shoes")
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
end
