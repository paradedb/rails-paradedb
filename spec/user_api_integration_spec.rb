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
  def test_matching_all_with_filters
    sql = Product.search(:description)
                 .matching_all("running", "shoes")
                 .where(in_stock: true)
                 .where("products.price < 100")
                 .where(rating: 4..)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'running shoes')
        AND "products"."in_stock" = true
        AND (products.price < 100)
        AND "products"."rating" >= 4
    SQL

    assert_sql_equal expected, sql
  end

  def test_closed_range_filter
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .where(price: 10..100)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes')
        AND "products"."price" BETWEEN 10 AND 100
    SQL

    assert_sql_equal expected, sql
  end

  def test_exclusive_end_range_filter
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .where(price: 10...100)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes')
        AND "products"."price" >= 10 AND "products"."price" < 100
    SQL

    assert_sql_equal expected, sql
  end

  def test_chain_multiple_search_fields_and
    sql = Product.search(:description).matching_all("running", "shoes")
                 .search(:category).phrase("Footwear")
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'running shoes') AND ("products"."category" ### 'Footwear')
    SQL

    assert_sql_equal expected, sql
  end

  def test_matching_any_or_semantics
    sql = Product.search(:description).matching_any("wireless", "bluetooth").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ||| 'wireless bluetooth')), sql
  end

  def test_excluding_terms
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .excluding("cheap", "budget")
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes') AND (NOT ("products"."description" &&& 'cheap budget'))
    SQL

    assert_sql_equal expected, sql
  end

  def test_phrase_with_slop
    sql = Product.search(:description).phrase("running shoes", slop: 2).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ### 'running shoes'::pdb.slop(2))), sql
  end

  def test_fuzzy_with_prefix
    sql = Product.search(:description).fuzzy("runn", distance: 1, prefix: true).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" === 'runn'::pdb.fuzzy(1, "true"))), sql
  end

  def test_regex
    sql = Product.search(:description).regex("run.*shoes").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.regex('run.*shoes'))), sql
  end

  def test_term_exact
    sql = Product.search(:description).term("shoes").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" === 'shoes')), sql
  end

  def test_near_proximity
    sql = Product.search(:description).near("sleek", "shoes", distance: 1).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## 'shoes'))), sql
  end

  def test_phrase_prefix
    sql = Product.search(:description).phrase_prefix("run", "sh").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh']))), sql
  end

  def test_parse_query
    sql = Product.search(:description).parse("running AND shoes", lenient: true).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes', lenient => true))), sql
  end

  def test_match_all_wrapper
    sql = Product.search(:id).match_all.to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.all())), sql
  end

  def test_more_like_this
    sql = Product.more_like_this(3, fields: [:description]).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this(3, ARRAY['description']))), sql
  end

  def test_with_score_and_order
    sql = Product.search(:description)
                 .matching_all("running", "shoes")
                 .with_score
                 .order(search_score: :desc)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.score("products"."id") AS search_score FROM products
      WHERE ("products"."description" &&& 'running shoes')
      ORDER BY search_score DESC
    SQL

    assert_sql_equal expected, sql
  end

  def test_with_snippet_default
    sql = Product.search(:description)
                 .matching_all("running shoes")
                 .with_snippet(:description)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippet("products"."description") AS description_snippet FROM products
      WHERE ("products"."description" &&& 'running shoes')
    SQL

    assert_sql_equal expected, sql
  end

  def test_with_snippet_custom
    sql = Product.search(:description)
                 .matching_all("running shoes")
                 .with_snippet(:description, start_tag: '<mark>', end_tag: '</mark>', max_chars: 100)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippet("products"."description", '<mark>', '</mark>', 100) AS description_snippet FROM products
      WHERE ("products"."description" &&& 'running shoes')
    SQL

    assert_sql_equal expected, sql
  end

  def test_with_score_then_with_snippet_keeps_both_projections
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .with_score
                 .with_snippet(:description)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.score("products"."id") AS search_score, pdb.snippet("products"."description") AS description_snippet FROM products
      WHERE ("products"."description" &&& 'shoes')
    SQL

    assert_sql_equal expected, sql
  end

  def test_with_snippet_then_with_score_keeps_both_projections
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .with_snippet(:description)
                 .with_score
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippet("products"."description") AS description_snippet, pdb.score("products"."id") AS search_score FROM products
      WHERE ("products"."description" &&& 'shoes')
    SQL

    assert_sql_equal expected, sql
  end

  def test_or_across_fields
    base = Product.where(in_stock: true).order(id: :desc).limit(10)
    left = base.search(:description).matching_all("shoes")
    right = base.search(:category).matching_all("footwear")

    sql = left.or(right).to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."in_stock" = TRUE AND ("products"."description" &&& 'shoes' OR "products"."category" &&& 'footwear')
      ORDER BY "products"."id" DESC
      LIMIT 10
    SQL

    assert_sql_equal expected, sql
  end

  def test_facets_only
    facet_sql = Product.search(:description).matching_all("shoes")
                       .build_facet_query(fields: [:category, :brand], size: 10, order: "-count")
                       .sql

    expected = %(SELECT pdb.agg('{"terms": {"field": "category", "size": 10, "order": {"_count": "desc"}}}') AS category_facet, pdb.agg('{"terms": {"field": "brand", "size": 10, "order": {"_count": "desc"}}}') AS brand_facet FROM (SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes')) paradedb_facet_source)

    assert_sql_equal expected, facet_sql
  end

  def test_with_facets_rows_plus_facets
    sql = Product.search(:description).matching_all("shoes")
                 .where(in_stock: true)
                 .with_facets(:category, :brand, size: 10)
                 .order(rating: :desc)
                 .limit(10)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.agg('{"terms": {"field": "category", "size": 10, "order": {"_count": "desc"}}}') OVER () AS _category_facet, pdb.agg('{"terms": {"field": "brand", "size": 10, "order": {"_count": "desc"}}}') OVER () AS _brand_facet FROM products
      WHERE ("products"."description" &&& 'shoes') AND "products"."in_stock" = true
      ORDER BY "products"."rating" DESC
      LIMIT 10
    SQL

    assert_sql_equal expected, sql
  end

  # ===== Tests combining ActiveRecord + ParadeDB features =====

  def test_search_on_scoped_relation_preserves_scope
    # Start with a scoped relation, then add search
    sql = Product.where(in_stock: true)
                 .where(price: 10..100)
                 .search(:description)
                 .matching_all("wireless")
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."in_stock" = true
        AND "products"."price" BETWEEN 10 AND 100
        AND ("products"."description" &&& 'wireless')
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_joins
    # Search combined with JOIN
    sql = Product.joins("LEFT JOIN categories ON products.category_id = categories.id")
                 .search(:description)
                 .matching_all("shoes")
                 .where("categories.active = true")
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      LEFT JOIN categories ON products.category_id = categories.id
      WHERE ("products"."description" &&& 'shoes')
        AND (categories.active = true)
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_group_and_having
    # Search with GROUP BY and HAVING
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .select("products.*, COUNT(*) as order_count")
                 .group("products.id")
                 .having("COUNT(*) > 5")
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, COUNT(*) as order_count FROM products
      WHERE ("products"."description" &&& 'shoes')
      GROUP BY products.id
      HAVING (COUNT(*) > 5)
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_offset_and_limit
    # Pagination with search
    sql = Product.search(:description)
                 .matching_all("wireless")
                 .where(in_stock: true)
                 .order(created_at: :desc)
                 .limit(20)
                 .offset(40)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'wireless')
        AND "products"."in_stock" = true
      ORDER BY created_at DESC
      LIMIT 20
      OFFSET 40
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_distinct
    # DISTINCT with search
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .distinct
                 .to_sql

    expected = <<~SQL.strip
      SELECT DISTINCT products.* FROM products
      WHERE ("products"."description" &&& 'shoes')
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_includes_reference
    # Search with includes (generates JOIN)
    sql = Product.where(in_stock: true)
                 .references(:categories)
                 .search(:description)
                 .matching_all("electronics")
                 .to_sql

    # Note: includes would trigger eager loading, but references just ensures JOIN
    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."in_stock" = true
        AND ("products"."description" &&& 'electronics')
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_multiple_orders
    # Multiple ORDER BY clauses
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .with_score
                 .order(search_score: :desc)
                 .order(created_at: :desc)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.score("products"."id") AS search_score FROM products
      WHERE ("products"."description" &&& 'shoes')
      ORDER BY search_score DESC, created_at DESC
    SQL

    assert_sql_equal expected, sql
  end

  def test_complex_or_with_where_conditions
    # Complex OR with different WHERE conditions on each side
    left = Product.where(price: 0..50)
                  .search(:description)
                  .matching_all("budget", "cheap")

    right = Product.where(rating: 4..)
                   .search(:description)
                   .matching_all("premium")

    sql = left.or(right).to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."price" BETWEEN 0 AND 50 AND ("products"."description" &&& 'budget cheap')
        OR "products"."rating" >= 4 AND ("products"."description" &&& 'premium'))
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_not_conditions
    # Search combined with NOT conditions
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .where.not(category: "Discontinued")
                 .where.not(in_stock: false)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes')
        AND "products"."category" != 'Discontinued'
        AND "products"."in_stock" != FALSE
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_in_condition
    # Search with IN clause
    sql = Product.search(:description)
                 .matching_all("wireless")
                 .where(category: ["Electronics", "Audio", "Video"])
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'wireless')
        AND "products"."category" IN ('Electronics', 'Audio', 'Video')
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_like_pattern
    # Search combined with LIKE
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .where("products.sku LIKE ?", "RUN-%")
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes')
        AND (products.sku LIKE 'RUN-%')
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_null_checks
    # Search with NULL checks
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .where.not(description: nil)
                 .where(discontinued_at: nil)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes')
        AND "products"."description" IS NOT NULL
        AND "products"."discontinued_at" IS NULL
    SQL

    assert_sql_equal expected, sql
  end

  def test_chained_search_fields_with_mixed_where
    # Multiple search fields with WHERE clauses interspersed
    sql = Product.where(in_stock: true)
                 .search(:description)
                 .matching_all("wireless")
                 .where(price: 0..200)
                 .search(:category)
                 .phrase("Electronics")
                 .where.not(rating: nil)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."in_stock" = true
        AND ("products"."description" &&& 'wireless')
        AND "products"."price" BETWEEN 0 AND 200
        AND ("products"."category" ### 'Electronics')
        AND "products"."rating" IS NOT NULL
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_subquery_in_where
    # Search with subquery
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .where("price < (SELECT AVG(price) FROM products)")
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes')
        AND (price < (SELECT AVG(price) FROM products))
    SQL

    assert_sql_equal expected, sql
  end

  def test_conditional_search_building
    # Simulating conditional query building (common pattern)
    query = Product.where(in_stock: true)
    
    # Conditionally add search
    query = query.search(:description).matching_all("wireless")
    
    # Conditionally add filters
    query = query.where(price: 0..100)
    
    # Conditionally add ordering
    query = query.order(rating: :desc).limit(10)
    
    sql = query.to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."in_stock" = true
        AND ("products"."description" &&& 'wireless')
        AND "products"."price" BETWEEN 0 AND 100
      ORDER BY "products"."rating" DESC
      LIMIT 10
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_readonly
    # Readonly doesn't affect SQL but ensures proper chaining
    sql = Product.search(:description)
                 .matching_all("shoes")
                 .readonly
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes')
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_on_relation_from_scope
    # Simulate a named scope returning a relation
    scoped = Product.where(in_stock: true).order(created_at: :desc)
    
    sql = scoped.search(:description)
                .matching_all("shoes")
                .limit(5)
                .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."in_stock" = true
        AND ("products"."description" &&& 'shoes')
      ORDER BY created_at DESC
      LIMIT 5
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_unscope
    # Unscope to remove certain conditions
    sql = Product.where(in_stock: true)
                 .order(created_at: :desc)
                 .search(:description)
                 .matching_all("shoes")
                 .unscope(:order)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."in_stock" = true
        AND ("products"."description" &&& 'shoes')
    SQL

    assert_sql_equal expected, sql
  end

  def test_search_with_rewhere
    # Rewhere to replace existing condition
    sql = Product.where(in_stock: true)
                 .search(:description)
                 .matching_all("shoes")
                 .rewhere(in_stock: false)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes')
        AND "products"."in_stock" = FALSE
    SQL

    assert_sql_equal expected, sql
  end
end
