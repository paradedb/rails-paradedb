# frozen_string_literal: true

require "spec_helper"

class Product < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
end

class Category < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :categories
end

RSpec.describe "UserApiUnitTest" do
  it "matching all with filters" do
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
  it "closed range filter" do
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
  it "exclusive end range filter" do
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
  it "chain multiple search fields and" do
    sql = Product.search(:description).matching_all("running", "shoes")
                 .search(:category).phrase("Footwear")
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'running shoes') AND ("products"."category" ### 'Footwear')
    SQL

    assert_sql_equal expected, sql
  end
  it "matching any or semantics" do
    sql = Product.search(:description).matching_any("wireless", "bluetooth").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ||| 'wireless bluetooth')), sql
  end
  it "matching all with tokenizer override" do
    sql = Product.search(:description).matching_all("running shoes", tokenizer: "whitespace").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" &&& 'running shoes'::pdb.whitespace)), sql
  end
  it "matching all with tokenizer args" do
    sql = Product.search(:description).matching_all("running shoes", tokenizer: "whitespace('lowercase=false')").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" &&& 'running shoes'::pdb.whitespace('lowercase=false'))), sql
  end
  it "excluding terms" do
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
  it "excluding" do
    sql = Product.search(:description).matching_all("shoes").excluding("cheap").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes') AND (NOT ("products"."description" &&& 'cheap'))), sql
  end
  it "or composition" do
    base = Product.where(in_stock: true).order(id: :desc).limit(10)
    left = base.search(:description).matching_all("shoes")
    right = base.search(:category).matching_all("footwear")
    sql = left.or(right).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE "products"."in_stock" = TRUE AND ("products"."description" &&& 'shoes' OR "products"."category" &&& 'footwear') ORDER BY "products"."id" DESC LIMIT 10), sql
  end
  it "phrase with slop" do
    sql = Product.search(:description).phrase("running shoes", slop: 2).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ### 'running shoes'::pdb.slop(2))), sql
  end
  it "phrase with tokenizer" do
    sql = Product.search(:description).phrase("running shoes", tokenizer: "whitespace").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ### 'running shoes'::pdb.whitespace)), sql
  end
  it "phrase with pretokenized array" do
    sql = Product.search(:description).phrase(%w[running shoes]).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ### ARRAY['running', 'shoes'])), sql
  end
  it "fuzzy with prefix" do
    sql = Product.search(:description).term("runn", distance: 1, prefix: true).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" === 'runn'::pdb.fuzzy(1, "true"))), sql
  end
  it "fuzzy with prefix and boost" do
    sql = Product.search(:description).term("shose", distance: 2, prefix: false, boost: 2).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(2))), sql
  end
  it "regex" do
    sql = Product.search(:description).regex("run.*shoes").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.regex('run.*shoes'))), sql
  end
  it "regex phrase" do
    sql = Product.search(:description).regex_phrase("run.*", "sho.*", slop: 2, max_expansions: 100).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.regex_phrase(ARRAY['run.*', 'sho.*'], slop => 2, max_expansions => 100))), sql
  end
  it "term exact" do
    sql = Product.search(:description).term("shoes").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" === 'shoes')), sql
  end
  it "term set" do
    sql = Product.search(:category).term_set("audio", "footwear").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."category" @@@ pdb.term_set(ARRAY['audio', 'footwear']))), sql
  end
  it "near proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("sleek").within(1, "shoes")).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## 'shoes'))), sql
  end
  it "near ordered proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("sleek").within(1, "shoes", ordered: true)).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ##> 1 ##> 'shoes'))), sql
  end
  it "near array proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("sleek", "white").within(1, "shoes")).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ (pdb.prox_array('sleek', 'white') ## 1 ## 'shoes'))), sql
  end
  it "near with regex wrapper" do
    sql = Product.search(:description).near(ParadeDB.regex_term("sl.*").within(1, "shoes")).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ (pdb.prox_regex('sl.*') ## 1 ## 'shoes'))), sql
  end
  it "near with mixed array left operand" do
    sql = Product.search(:description).near(ParadeDB.proximity(ParadeDB.regex_term("sl.*"), "white").within(1, "shoes")).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ (pdb.prox_array(pdb.prox_regex('sl.*'), 'white') ## 1 ## 'shoes'))), sql
  end
  it "near with array right operand" do
    sql = Product.search(:description).near(ParadeDB.proximity("sleek").within(1, "white", "shoes")).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## pdb.prox_array('white', 'shoes')))), sql
  end
  it "near chained proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("trail").within(1, "running").within(1, "shoes")).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ (('trail' ## 1 ## 'running') ## 1 ## 'shoes'))), sql
  end
  it "near chained proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("trail").within(1, ParadeDB.proximity("running").within(1, "shoes"))).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('trail' ## 1 ## ('running' ## 1 ## 'shoes')))), sql
  end
  it "near boosted proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("sleek").within(1, "shoes"), boost: 2.0).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## 'shoes')::pdb.boost(2.0))), sql
  end
  it "near constant score proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("sleek").within(1, "shoes"), const: 1.0).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## 'shoes')::pdb.const(1.0))), sql
  end
  it "phrase prefix" do
    sql = Product.search(:description).phrase_prefix("run", "sh").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh']))), sql
  end
  it "phrase prefix with max expansion" do
    sql = Product.search(:description).phrase_prefix("run", "sh", max_expansion: 100).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh'], 100))), sql
  end
  it "parse query" do
    sql = Product.search(:description).parse("running AND shoes", lenient: true).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes', lenient => true))), sql
  end
  it "parse query with conjunction mode" do
    sql = Product.search(:description).parse("running shoes", conjunction_mode: true).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running shoes', conjunction_mode => true))), sql
  end
  it "parse query without options" do
    sql = Product.search(:description).parse("running AND shoes").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes'))), sql
  end
  it "parse query with lenient false" do
    sql = Product.search(:description).parse("running AND shoes", lenient: false).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes', lenient => false))), sql
  end
  it "match all wrapper" do
    sql = Product.search(:id).match_all.to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.all())), sql
  end
  it "exists wrapper" do
    sql = Product.search(:id).exists.to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.exists())), sql
  end
  it "range wrapper with Ruby range" do
    sql = Product.search(:rating).range(3..5).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."rating" @@@ pdb.range(int8range(3, 5, '[]')))), sql
  end
  it "range wrapper with bound options" do
    sql = Product.search(:rating).range(gte: 3, lt: 5).to_sql
    assert_sql_equal %q{SELECT products.* FROM products WHERE ("products"."rating" @@@ pdb.range(int8range(3, 5, '[)')))}, sql
  end
  it "range term relation" do
    sql = Product.search(:weight_range).range_term("(10, 12]", relation: "Intersects", range_type: "int4range").to_sql
    assert_sql_equal %q{SELECT products.* FROM products WHERE ("products"."weight_range" @@@ pdb.range_term('(10, 12]'::int4range, 'Intersects'))}, sql
  end
  it "range term scalar value" do
    sql = Product.search(:weight_range).range_term(1).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."weight_range" @@@ pdb.range_term(1))), sql
  end
  it "more like this" do
    sql = Product.more_like_this(3, fields: [:description]).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this(3, ARRAY['description']))), sql
  end
  it "more like this with json string" do
    sql = Product.more_like_this('{"description": "running shoes"}').to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this('{"description": "running shoes"}'))), sql
  end
  it "more like this with json and fields" do
    sql = Product.more_like_this('{"description": "running shoes", "category": "footwear"}', fields: [:description, :category]).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this('{"description": "running shoes", "category": "footwear"}', ARRAY['description', 'category']))), sql
  end
  it "more like this with json hash" do
    json_doc = { description: "running shoes", category: "footwear" }.to_json
    sql = Product.more_like_this(json_doc).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this('{"description":"running shoes","category":"footwear"}'))), sql
  end
  it "more like this with advanced options" do
    sql = Product.more_like_this(
      5,
      fields: [:description],
      min_term_freq: 2,
      max_query_terms: 10,
      min_doc_freq: 1,
      max_term_freq: 20,
      max_doc_freq: 200,
      min_word_length: 3,
      max_word_length: 15,
      stopwords: %w[the a]
    ).to_sql

    expected = %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this(5, ARRAY['description'], min_term_frequency => 2, max_query_terms => 10, min_doc_frequency => 1, max_term_frequency => 20, max_doc_frequency => 200, min_word_length => 3, max_word_length => 15, stopwords => ARRAY['the', 'a'])))
    assert_sql_equal expected, sql
  end
  it "more like this key extraction does not fallback to id for non-id key fields" do
    relation = Product.all.extending(ParadeDB::SearchMethods)
    key = Struct.new(:id).new(42)

    error = assert_raises(ArgumentError) { relation.send(:more_like_this_key_value, key, :external_id) }
    assert_includes error.message, "external_id"
    assert_equal 42, relation.send(:more_like_this_key_value, key, :id)
  end
  it "with score and order" do
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
  it "with score" do
    sql = Product.search(:description).matching_all("shoes").with_score.to_sql
    assert_sql_equal %(SELECT products.*, pdb.score("products"."id") AS search_score FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippet default" do
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
  it "with snippet custom" do
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
  it "with snippets custom options" do
    sql = Product.search(:description)
                 .matching_all("running shoes")
                 .with_snippets(:description, max_chars: 15, limit: 1, offset: 0, sort_by: :position)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippets("products"."description", max_num_chars => 15, "limit" => 1, "offset" => 0, sort_by => 'position') AS description_snippets FROM products
      WHERE ("products"."description" &&& 'running shoes')
    SQL

    assert_sql_equal expected, sql
  end
  it "with snippet positions" do
    sql = Product.search(:description)
                 .matching_all("running shoes")
                 .with_snippet_positions(:description)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippet_positions("products"."description") AS description_snippet_positions FROM products
      WHERE ("products"."description" &&& 'running shoes')
    SQL

    assert_sql_equal expected, sql
  end
  it "with score then with snippet keeps both projections" do
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
  it "with snippet then with score keeps both projections" do
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
  it "with snippets default alias" do
    sql = Product.search(:description).matching_all("shoes")
                     .with_snippets(:description, max_chars: 30, limit: 1, offset: 0, sort_by: :position)
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.snippets("products"."description", max_num_chars => 30, "limit" => 1, "offset" => 0, sort_by => 'position') AS description_snippets FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippets custom alias" do
    sql = Product.search(:description).matching_all("shoes")
                     .with_snippets(:description, as: :all_snips)
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.snippets("products"."description") AS all_snips FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippet positions default alias" do
    sql = Product.search(:description).matching_all("shoes")
                     .with_snippet_positions(:description)
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.snippet_positions("products"."description") AS description_snippet_positions FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippet positions custom alias" do
    sql = Product.search(:description).matching_all("shoes")
                     .with_snippet_positions(:description, as: "positions")
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.snippet_positions("products"."description") AS positions FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "or across fields" do
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
  it "facets only" do
    facet_sql = Product.search(:description).matching_all("shoes")
                       .build_facet_query(fields: [:category, :brand], size: 10, order: :count_desc)
                       .sql

    expected = %(SELECT pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') AS category_facet, pdb.agg('{"terms":{"field":"brand","size":10,"order":{"_count":"desc"}}}') AS brand_facet FROM (SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes')) paradedb_facet_source)

    assert_sql_equal expected, facet_sql
  end
  it "with facets rows plus facets" do
    sql = Product.search(:description).matching_all("shoes")
                 .where(in_stock: true)
                 .with_facets(:category, :brand, size: 10)
                 .order(rating: :desc)
                 .limit(10)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') OVER () AS _category_facet, pdb.agg('{"terms":{"field":"brand","size":10,"order":{"_count":"desc"}}}') OVER () AS _brand_facet FROM products
      WHERE ("products"."description" &&& 'shoes') AND "products"."in_stock" = true
      ORDER BY "products"."rating" DESC
      LIMIT 10
    SQL

    assert_sql_equal expected, sql
  end
  it "with facets exact false emits second agg argument" do
    sql = Product.search(:description).matching_all("shoes")
                 .with_facets(:category, size: 10, exact: false)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}', false) OVER () AS _category_facet FROM products
      WHERE ("products"."description" &&& 'shoes')
    SQL

    assert_sql_equal expected, sql
  end
  it "facets with custom agg without fields still projects aggregate" do
    facet_sql = Product.search(:description).matching_all("shoes")
                           .build_facet_query(
                             fields: [],
                             size: 99,
                             order: :count_asc,
                             missing: "(missing)",
                             agg: { "value_count" => { "field" => "id" } }
                           )
                           .sql

    assert_includes facet_sql, %(pdb.agg('{"value_count":{"field":"id"}}'))
    refute_includes facet_sql, %({"terms":)
    refute_includes facet_sql, %("size":)
    refute_includes facet_sql, %("_count")
  end
  it "facets without paradedb predicates" do
    facet_sql = Product.where(in_stock: true)
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    expected = %(SELECT pdb.agg('{\"terms\":{\"field\":\"category\",\"size\":10}}') AS category_facet FROM (SELECT products.* FROM products WHERE \"products\".\"in_stock\" = TRUE AND (\"products\".\"id\" @@@ pdb.all())) paradedb_facet_source)

    assert_sql_equal expected, facet_sql
  end
  it "facets with no predicates" do
    facet_sql = Product.all
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 5, order: nil)
                           .sql

    expected = %(SELECT pdb.agg('{\"terms\":{\"field\":\"category\",\"size\":5}}') AS category_facet FROM (SELECT products.* FROM products WHERE (\"products\".\"id\" @@@ pdb.all())) paradedb_facet_source)

    assert_sql_equal expected, facet_sql
  end
  it "facets with size nil omits size clause" do
    facet_sql = Product.search(:description).matching_all("shoes")
                           .build_facet_query(fields: [:category], size: nil, order: nil)
                           .sql

    expected = %(SELECT pdb.agg('{"terms":{"field":"category"}}') AS category_facet FROM (SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes')) paradedb_facet_source)
    assert_sql_equal expected, facet_sql
  end
  it "facets with raw paradedb sql predicate does not append match all" do
    facet_sql = Product.where(Arel.sql(%("products"."description" @@@ pdb.regex('run.*'))))
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_includes facet_sql, %("products"."description" @@@ pdb.regex('run.*'))
    refute_includes facet_sql, %("products"."id" @@@ pdb.all())
  end
  it "facets with non paradedb sql predicate appends match all" do
    facet_sql = Product.where(Arel.sql(%("products"."price" > 50)))
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_includes facet_sql, %("products"."price" > 50)
    assert_includes facet_sql, %("products"."id" @@@ pdb.all())
  end
  it "facets with mixed paradedb and standard predicates keeps existing paradedb predicate" do
    facet_sql = Product.where(in_stock: true)
                           .search(:description)
                           .matching_all("shoes")
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_includes facet_sql, %("products"."in_stock" = TRUE)
    assert_includes facet_sql, %("products"."description" &&& 'shoes')
    refute_includes facet_sql, %("products"."id" @@@ pdb.all())
  end
  it "with facets without paradedb predicates" do
    sql = Product.where(in_stock: true)
                     .extending(ParadeDB::SearchMethods)
                     .with_facets(:category, size: 10)
                     .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') OVER () AS _category_facet FROM products
      WHERE "products"."in_stock" = TRUE AND ("products"."id" @@@ pdb.all())
    SQL

    assert_sql_equal expected, sql
  end
  it "with facets default order is desc count" do
    sql = Product.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)
                     .to_sql

    expected = %(SELECT products.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') OVER () AS _category_facet FROM products WHERE ("products"."description" &&& 'shoes'))
    assert_sql_equal expected, sql
  end
  it "with facets exact false emits second agg argument" do
    sql = Product.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10, exact: false)
                     .to_sql

    expected = %(SELECT products.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}', false) OVER () AS _category_facet FROM products WHERE ("products"."description" &&& 'shoes'))
    assert_sql_equal expected, sql
  end
  it "facets exact false raises" do
    error = assert_raises(ArgumentError) do
      Product.search(:description).matching_all("shoes").facets(:category, exact: false)
    end
    assert_includes error.message, "facets(exact: false)"
  end
  it "with facets uses custom agg and ignores field size order missing" do
    sql = Product.search(:description)
                     .matching_all("shoes")
                     .with_facets(
                       :category,
                       size: 20,
                       order: :count_desc,
                       missing: "(missing)",
                       agg: { "value_count" => { "field" => "id" } }
                     )
                     .to_sql

    assert_includes sql, %(pdb.agg('{"value_count":{"field":"id"}}') OVER ())
    refute_includes sql, %({"terms":)
    refute_includes sql, %("field": "category")
    refute_includes sql, %("size": 20)
    refute_includes sql, %("missing":)
  end
  it "facets_agg builds one pdb.agg projection per named aggregation" do
    facet_sql = Product.search(:description)
                           .matching_all("shoes")
                           .send(
                             :build_aggregation_query,
                             Product.search(:description)
                                        .matching_all("shoes")
                                        .send(
                                          :normalize_named_aggregation_specs,
                                          docs: ParadeDB::Aggregations.value_count(:id),
                                          avg_rating: ParadeDB::Aggregations.avg(:rating)
                                        )
                           )
                           .sql

    assert_includes facet_sql, %(pdb.agg('{"value_count":{"field":"id"}}') AS docs_facet)
    assert_includes facet_sql, %(pdb.agg('{"avg":{"field":"rating"}}') AS avg_rating_facet)
  end
  it "with_agg adds multiple window aggregates" do
    sql = Product.search(:description)
                     .matching_all("shoes")
                     .with_agg(
                       docs: ParadeDB::Aggregations.value_count(:id),
                       avg_rating: ParadeDB::Aggregations.avg(:rating)
                     )
                     .to_sql

    assert_includes sql, %(pdb.agg('{"value_count":{"field":"id"}}') OVER () AS _docs_facet)
    assert_includes sql, %(pdb.agg('{"avg":{"field":"rating"}}') OVER () AS _avg_rating_facet)
  end
  it "with_agg exact false emits second agg argument" do
    sql = Product.search(:description)
                     .matching_all("shoes")
                     .with_agg(
                       exact: false,
                       docs: ParadeDB::Aggregations.value_count(:id)
                     )
                     .to_sql

    assert_includes sql, %(pdb.agg('{"value_count":{"field":"id"}}', FALSE) OVER () AS _docs_facet)
  end
  it "with_agg supports filtered named aggregations" do
    sql = Product.with_agg(
      electronics_count: ParadeDB::Aggregations.filtered(
        ParadeDB::Aggregations.value_count(:id),
        field: :category,
        term: "electronics"
      )
    ).to_sql

    assert_includes sql, %(pdb.agg('{"value_count":{"field":"id"}}') FILTER (WHERE "products"."category" === 'electronics') OVER () AS _electronics_count_facet)
    assert_includes sql, %("products"."id" @@@ pdb.all())
  end
  it "facets_agg supports filtered named aggregations" do
    facet_sql = Product.search(:description)
                           .matching_all("shoes")
                           .send(
                             :build_aggregation_query,
                             Product.search(:description)
                                        .matching_all("shoes")
                                        .send(
                                          :normalize_named_aggregation_specs,
                                          electronics_count: ParadeDB::Aggregations.filtered(
                                            ParadeDB::Aggregations.value_count(:id),
                                            field: :category,
                                            term: "electronics"
                                          )
                                        )
                           )
                           .sql

    assert_includes facet_sql, %(pdb.agg('{"value_count":{"field":"id"}}') FILTER (WHERE "paradedb_agg_source"."category" === 'electronics') AS electronics_count_facet)
  end
  it "model with_agg class helper delegates to relation api" do
    sql = Product.with_agg(docs: ParadeDB::Aggregations.value_count(:id)).to_sql

    assert_includes sql, %(pdb.agg('{"value_count":{"field":"id"}}') OVER () AS _docs_facet)
    assert_includes sql, %("products"."id" @@@ pdb.all())
  end
  it "aggregate_by builds grouped aggregation query" do
    sql = Product.search(:category)
                     .term("electronics")
                     .aggregate_by(
                       :rating,
                       agg: ParadeDB::Aggregations.value_count(:id)
                     )
                     .order(:rating)
                     .limit(5)
                     .to_sql

    expected = <<~SQL.strip
      SELECT "products"."rating", pdb.agg('{"value_count":{"field":"id"}}') AS agg FROM "products"
      WHERE ("products"."category" === 'electronics')
      GROUP BY "products"."rating"
      ORDER BY "products"."rating" ASC
      LIMIT 5
    SQL

    assert_sql_equal expected, sql
  end
  it "model aggregate_by adds match all when no paradedb predicate exists" do
    sql = Product.aggregate_by(:rating, agg: ParadeDB::Aggregations.value_count(:id)).to_sql

    assert_includes sql, %("products"."id" @@@ pdb.all())
    assert_includes sql, %(GROUP BY "products"."rating")
    assert_includes sql, %(pdb.agg('{"value_count":{"field":"id"}}') AS agg)
  end
  it "with facets load requires order and limit" do
    rel = Product.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY and LIMIT"
  end
  it "with facets load requires limit" do
    rel = Product.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)
                     .order(:id)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "LIMIT"
  end
  it "with facets load requires order" do
    rel = Product.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)
                     .limit(10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY"
  end
  it "search on relation preserves where" do
    # Verify .search() works on relations and preserves WHERE clauses
    sql = Product.where(in_stock: true)
                     .search(:description)
                     .matching_all("shoes")
                     .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."in_stock" = TRUE AND ("products"."description" &&& 'shoes')
    SQL

    assert_sql_equal expected, sql
  end
  it "search on relation preserves order and limit" do
    # Verify .search() preserves ORDER BY and LIMIT
    sql = Product.where(price: 0..100)
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

  # ===== Tests combining ActiveRecord + ParadeDB features =====
  it "search on scoped relation preserves scope" do
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
  it "search with joins" do
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
  it "search with group and having" do
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
  it "search with offset and limit" do
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
  it "search with distinct" do
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
  it "search with includes reference" do
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
  it "search with multiple orders" do
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
  it "complex or with where conditions" do
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
  it "search with not conditions" do
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
  it "search with in condition" do
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
  it "search with like pattern" do
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
  it "search with null checks" do
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
  it "chained search fields with mixed where" do
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
  it "search with subquery in where" do
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
  it "conditional search building" do
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
  it "search with readonly" do
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
  it "search on relation from scope" do
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
  it "search with unscope" do
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
  it "search with rewhere" do
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
