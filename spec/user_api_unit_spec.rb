# frozen_string_literal: true

require "spec_helper"

class UnitProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
end

class UnitCategory < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :categories
end

RSpec.describe "UserApiUnitTest" do
  it "matching all and filters" do
    sql = UnitProduct.search(:description)
                     .matching_all("running", "shoes")
                     .where(in_stock: true)
                     .to_sql

    assert_sql_equal %(SELECT products.* FROM products
      WHERE ("products"."description" &&& 'running shoes') AND "products"."in_stock" = TRUE), sql
  end
  it "matching any" do
    sql = UnitProduct.search(:description).matching_any("wireless", "bluetooth").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ||| 'wireless bluetooth')), sql
  end
  it "matching all with tokenizer override" do
    sql = UnitProduct.search(:description).matching_all("running shoes", tokenizer: "whitespace").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" &&& 'running shoes'::pdb.whitespace)), sql
  end
  it "matching all with tokenizer args" do
    sql = UnitProduct.search(:description).matching_all("running shoes", tokenizer: "whitespace('lowercase=false')").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" &&& 'running shoes'::pdb.whitespace('lowercase=false'))), sql
  end
  it "phrase slop" do
    sql = UnitProduct.search(:description).phrase("running shoes", slop: 2).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ### 'running shoes'::pdb.slop(2))), sql
  end
  it "phrase tokenizer override" do
    sql = UnitProduct.search(:description).phrase("running shoes", tokenizer: "whitespace").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ### 'running shoes'::pdb.whitespace)), sql
  end
  it "phrase with pretokenized array" do
    sql = UnitProduct.search(:description).phrase(%w[running shoes]).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" ### ARRAY['running', 'shoes'])), sql
  end
  it "fuzzy prefix boost" do
    sql = UnitProduct.search(:description).term("shose", distance: 2, prefix: false, boost: 2).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(2))), sql
  end
  it "term exact" do
    sql = UnitProduct.search(:description).term("literal").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" === 'literal')), sql
  end
  it "term set wrapper" do
    sql = UnitProduct.search(:category).term_set("audio", "footwear").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."category" @@@ pdb.term_set(ARRAY['audio', 'footwear']))), sql
  end
  it "regex" do
    sql = UnitProduct.search(:description).regex("run.*").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.regex('run.*'))), sql
  end
  it "regex phrase" do
    sql = UnitProduct.search(:description).regex_phrase("run.*", "sho.*", slop: 2, max_expansions: 100).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.regex_phrase(ARRAY['run.*', 'sho.*'], slop => 2, max_expansions => 100))), sql
  end
  it "near" do
    sql = UnitProduct.search(:description).near("sleek", anchor: "shoes", distance: 1).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## 'shoes'))), sql
  end
  it "near ordered" do
    sql = UnitProduct.search(:description).near("sleek", anchor: "shoes", distance: 1, ordered: true).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ##> 1 ##> 'shoes'))), sql
  end
  it "near with array left operand" do
    sql = UnitProduct.search(:description).near("sleek", "white", anchor: "shoes", distance: 1).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ (pdb.prox_array('sleek', 'white') ## 1 ## 'shoes'))), sql
  end
  it "near with regex wrapper" do
    sql = UnitProduct.search(:description).near(ParadeDB.regex_term("sl.*"), anchor: "shoes", distance: 1).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ (pdb.prox_regex('sl.*') ## 1 ## 'shoes'))), sql
  end
  it "near with mixed array left operand" do
    sql = UnitProduct.search(:description).near(ParadeDB.regex_term("sl.*"), "white", anchor: "shoes", distance: 1).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ (pdb.prox_array(pdb.prox_regex('sl.*'), 'white') ## 1 ## 'shoes'))), sql
  end
  it "phrase prefix" do
    sql = UnitProduct.search(:description).phrase_prefix("run", "sh").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh']))), sql
  end
  it "phrase prefix with max expansion" do
    sql = UnitProduct.search(:description).phrase_prefix("run", "sh", max_expansion: 100).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh'], 100))), sql
  end
  it "parse query with lenient" do
    sql = UnitProduct.search(:description).parse("running AND shoes", lenient: true).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes', lenient => true))), sql
  end
  it "parse query without options" do
    sql = UnitProduct.search(:description).parse("running AND shoes").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes'))), sql
  end
  it "parse query with lenient false" do
    sql = UnitProduct.search(:description).parse("running AND shoes", lenient: false).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes', lenient => false))), sql
  end
  it "parse query with conjunction mode" do
    sql = UnitProduct.search(:description).parse("running shoes", conjunction_mode: true).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running shoes', conjunction_mode => true))), sql
  end
  it "match all wrapper" do
    sql = UnitProduct.search(:id).match_all.to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.all())), sql
  end
  it "exists wrapper" do
    sql = UnitProduct.search(:id).exists.to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.exists())), sql
  end
  it "range wrapper with Ruby range" do
    sql = UnitProduct.search(:rating).range(3..5).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."rating" @@@ pdb.range(int8range(3, 5, '[]')))), sql
  end
  it "range wrapper with bound options" do
    sql = UnitProduct.search(:rating).range(gte: 3, lt: 5).to_sql
    assert_sql_equal %q{SELECT products.* FROM products WHERE ("products"."rating" @@@ pdb.range(int8range(3, 5, '[)')))}, sql
  end
  it "range term scalar value" do
    sql = UnitProduct.search(:weight_range).range_term(1).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."weight_range" @@@ pdb.range_term(1))), sql
  end
  it "range term relation" do
    sql = UnitProduct.search(:weight_range).range_term("(10, 12]", relation: "Intersects", range_type: "int4range").to_sql
    assert_sql_equal %q{SELECT products.* FROM products WHERE ("products"."weight_range" @@@ pdb.range_term('(10, 12]'::int4range, 'Intersects'))}, sql
  end
  it "more like this with id" do
    sql = UnitProduct.more_like_this(5, fields: [:description]).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this(5, ARRAY['description']))), sql
  end
  it "more like this with json string" do
    sql = UnitProduct.more_like_this('{"description": "running shoes"}').to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this('{"description": "running shoes"}'))), sql
  end
  it "more like this with json and fields" do
    sql = UnitProduct.more_like_this('{"description": "running shoes", "category": "footwear"}', fields: [:description, :category]).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this('{"description": "running shoes", "category": "footwear"}', ARRAY['description', 'category']))), sql
  end
  it "more like this with json hash" do
    json_doc = { description: "running shoes", category: "footwear" }.to_json
    sql = UnitProduct.more_like_this(json_doc).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this('{"description":"running shoes","category":"footwear"}'))), sql
  end
  it "more like this with advanced options" do
    sql = UnitProduct.more_like_this(
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
    relation = UnitProduct.all.extending(ParadeDB::SearchMethods)
    key = Struct.new(:id).new(42)

    error = assert_raises(ArgumentError) { relation.send(:more_like_this_key_value, key, :external_id) }
    assert_includes error.message, "external_id"
    assert_equal 42, relation.send(:more_like_this_key_value, key, :id)
  end
  it "excluding" do
    sql = UnitProduct.search(:description).matching_all("shoes").excluding("cheap").to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes') AND (NOT ("products"."description" &&& 'cheap'))), sql
  end
  it "or composition" do
    base = UnitProduct.where(in_stock: true).order(id: :desc).limit(10)
    left = base.search(:description).matching_all("shoes")
    right = base.search(:category).matching_all("footwear")
    sql = left.or(right).to_sql
    assert_sql_equal %(SELECT products.* FROM products WHERE "products"."in_stock" = TRUE AND ("products"."description" &&& 'shoes' OR "products"."category" &&& 'footwear') ORDER BY "products"."id" DESC LIMIT 10), sql
  end
  it "with score" do
    sql = UnitProduct.search(:description).matching_all("shoes").with_score.to_sql
    assert_sql_equal %(SELECT products.*, pdb.score("products"."id") AS search_score FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippet default" do
    sql = UnitProduct.search(:description).matching_all("shoes").with_snippet(:description).to_sql
    assert_sql_equal %(SELECT products.*, pdb.snippet("products"."description") AS description_snippet FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippet custom" do
    sql = UnitProduct.search(:description).matching_all("shoes").with_snippet(:description, start_tag: "<b>", end_tag: "</b>", max_chars: 50).to_sql
    assert_sql_equal %(SELECT products.*, pdb.snippet("products"."description", '<b>', '</b>', 50) AS description_snippet FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippets default alias" do
    sql = UnitProduct.search(:description).matching_all("shoes")
                     .with_snippets(:description, max_chars: 30, limit: 1, offset: 0, sort_by: :position)
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.snippets("products"."description", max_num_chars => 30, "limit" => 1, "offset" => 0, sort_by => 'position') AS description_snippets FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippets custom alias" do
    sql = UnitProduct.search(:description).matching_all("shoes")
                     .with_snippets(:description, as: :all_snips)
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.snippets("products"."description") AS all_snips FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippet positions default alias" do
    sql = UnitProduct.search(:description).matching_all("shoes")
                     .with_snippet_positions(:description)
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.snippet_positions("products"."description") AS description_snippet_positions FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippet positions custom alias" do
    sql = UnitProduct.search(:description).matching_all("shoes")
                     .with_snippet_positions(:description, as: "positions")
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.snippet_positions("products"."description") AS positions FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with score then with snippet keeps both projections" do
    sql = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_score
                     .with_snippet(:description)
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.score("products"."id") AS search_score, pdb.snippet("products"."description") AS description_snippet FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippet then with score keeps both projections" do
    sql = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_snippet(:description)
                     .with_score
                     .to_sql

    assert_sql_equal %(SELECT products.*, pdb.snippet("products"."description") AS description_snippet, pdb.score("products"."id") AS search_score FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "facets only" do
    facet_sql = UnitProduct.search(:description).matching_all("shoes")
                           .build_facet_query(fields: [:category, :brand], size: 10, order: :count_desc)
                           .sql

    expected = %(SELECT pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') AS category_facet, pdb.agg('{"terms":{"field":"brand","size":10,"order":{"_count":"desc"}}}') AS brand_facet FROM (SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes')) paradedb_facet_source)

    assert_sql_equal expected, facet_sql
  end
  it "facets with custom agg without fields still projects aggregate" do
    facet_sql = UnitProduct.search(:description).matching_all("shoes")
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
    facet_sql = UnitProduct.where(in_stock: true)
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    expected = %(SELECT pdb.agg('{\"terms\":{\"field\":\"category\",\"size\":10}}') AS category_facet FROM (SELECT products.* FROM products WHERE \"products\".\"in_stock\" = TRUE AND (\"products\".\"id\" @@@ pdb.all())) paradedb_facet_source)

    assert_sql_equal expected, facet_sql
  end
  it "facets with no predicates" do
    facet_sql = UnitProduct.all
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 5, order: nil)
                           .sql

    expected = %(SELECT pdb.agg('{\"terms\":{\"field\":\"category\",\"size\":5}}') AS category_facet FROM (SELECT products.* FROM products WHERE (\"products\".\"id\" @@@ pdb.all())) paradedb_facet_source)

    assert_sql_equal expected, facet_sql
  end
  it "facets with size nil omits size clause" do
    facet_sql = UnitProduct.search(:description).matching_all("shoes")
                           .build_facet_query(fields: [:category], size: nil, order: nil)
                           .sql

    expected = %(SELECT pdb.agg('{"terms":{"field":"category"}}') AS category_facet FROM (SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes')) paradedb_facet_source)
    assert_sql_equal expected, facet_sql
  end
  it "facets with raw paradedb sql predicate does not append match all" do
    facet_sql = UnitProduct.where(Arel.sql(%("products"."description" @@@ pdb.regex('run.*'))))
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_includes facet_sql, %("products"."description" @@@ pdb.regex('run.*'))
    refute_includes facet_sql, %("products"."id" @@@ pdb.all())
  end
  it "facets with non paradedb sql predicate appends match all" do
    facet_sql = UnitProduct.where(Arel.sql(%("products"."price" > 50)))
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_includes facet_sql, %("products"."price" > 50)
    assert_includes facet_sql, %("products"."id" @@@ pdb.all())
  end
  it "facets with mixed paradedb and standard predicates keeps existing paradedb predicate" do
    facet_sql = UnitProduct.where(in_stock: true)
                           .search(:description)
                           .matching_all("shoes")
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_includes facet_sql, %("products"."in_stock" = TRUE)
    assert_includes facet_sql, %("products"."description" &&& 'shoes')
    refute_includes facet_sql, %("products"."id" @@@ pdb.all())
  end
  it "with facets without paradedb predicates" do
    sql = UnitProduct.where(in_stock: true)
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
    sql = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)
                     .to_sql

    expected = %(SELECT products.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') OVER () AS _category_facet FROM products WHERE ("products"."description" &&& 'shoes'))
    assert_sql_equal expected, sql
  end
  it "with facets exact false emits second agg argument" do
    sql = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10, exact: false)
                     .to_sql

    expected = %(SELECT products.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}', false) OVER () AS _category_facet FROM products WHERE ("products"."description" &&& 'shoes'))
    assert_sql_equal expected, sql
  end
  it "facets exact false raises" do
    error = assert_raises(ArgumentError) do
      UnitProduct.search(:description).matching_all("shoes").facets(:category, exact: false)
    end
    assert_includes error.message, "facets(exact: false)"
  end
  it "with facets uses custom agg and ignores field size order missing" do
    sql = UnitProduct.search(:description)
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
    facet_sql = UnitProduct.search(:description)
                           .matching_all("shoes")
                           .send(
                             :build_aggregation_query,
                             UnitProduct.search(:description)
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
    sql = UnitProduct.search(:description)
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
    sql = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_agg(
                       exact: false,
                       docs: ParadeDB::Aggregations.value_count(:id)
                     )
                     .to_sql

    assert_includes sql, %(pdb.agg('{"value_count":{"field":"id"}}', FALSE) OVER () AS _docs_facet)
  end
  it "with_agg supports filtered named aggregations" do
    sql = UnitProduct.with_agg(
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
    facet_sql = UnitProduct.search(:description)
                           .matching_all("shoes")
                           .send(
                             :build_aggregation_query,
                             UnitProduct.search(:description)
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
  it "facets_agg exact false raises" do
    error = assert_raises(ArgumentError) do
      UnitProduct.search(:description).matching_all("shoes").facets_agg(
        exact: false,
        docs: ParadeDB::Aggregations.value_count(:id)
      )
    end
    assert_includes error.message, "facets_agg(exact: false)"
  end
  it "model with_agg class helper delegates to relation api" do
    sql = UnitProduct.with_agg(docs: ParadeDB::Aggregations.value_count(:id)).to_sql

    assert_includes sql, %(pdb.agg('{"value_count":{"field":"id"}}') OVER () AS _docs_facet)
    assert_includes sql, %("products"."id" @@@ pdb.all())
  end
  it "aggregate_by builds grouped aggregation query" do
    sql = UnitProduct.search(:category)
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
    sql = UnitProduct.aggregate_by(:rating, agg: ParadeDB::Aggregations.value_count(:id)).to_sql

    assert_includes sql, %("products"."id" @@@ pdb.all())
    assert_includes sql, %(GROUP BY "products"."rating")
    assert_includes sql, %(pdb.agg('{"value_count":{"field":"id"}}') AS agg)
  end
  it "with facets load requires order and limit" do
    rel = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY and LIMIT"
  end
  it "with facets load requires limit" do
    rel = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)
                     .order(:id)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "LIMIT"
  end
  it "with facets load requires order" do
    rel = UnitProduct.search(:description)
                     .matching_all("shoes")
                     .with_facets(:category, size: 10)
                     .limit(10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY"
  end
  it "search on relation preserves where" do
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
  it "search on relation preserves order and limit" do
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
