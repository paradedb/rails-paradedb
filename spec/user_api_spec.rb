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

class VectorIndexedProductIndex < ParadeDB::Index
  self.table_name = :products
  self.key_field = :id
  self.index_name = :products_vector_search_idx
  self.fields = {
    id: {},
    description: nil,
    embedding: { metric: :cosine }
  }
end

class VectorIndexedProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products

  paradedb_index VectorIndexedProductIndex
end

RSpec.describe "UserApi" do
  before(:context) { setup_test_index }

  it "matching all with filters" do
    sql = Product.search(:description)
                 .match_all("running shoes")
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

    assert_query_sql expected, sql
  end
  it "chain multiple search fields and" do
    sql = Product.search(:description).match_all("running shoes")
                 .search(:category).phrase("Footwear")
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'running shoes') AND ("products"."category" ### 'Footwear')
    SQL

    assert_query_sql expected, sql
  end
  it "matching any or semantics" do
    sql = Product.search(:description).match_any("wireless bluetooth").to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" ||| 'wireless bluetooth')), sql
  end
  it "matching all with supported tokenizers" do
    [
      ["pdb.whitespace", ParadeDB::Tokenizer.whitespace()],
      ["pdb.whitespace('alias=my_column')", ParadeDB::Tokenizer.whitespace(options: {alias: "my_column"})],
      ["pdb.unicode_words", ParadeDB::Tokenizer.unicode_words()],
      ["pdb.literal", ParadeDB::Tokenizer.literal()],
      ["pdb.literal_normalized", ParadeDB::Tokenizer.literal_normalized()],
      ["pdb.ngram(3,3)", ParadeDB::Tokenizer.ngram(3, 3)],
      ["pdb.ngram(3,3,'positions=true')", ParadeDB::Tokenizer.ngram(3, 3, options: {positions: true})],
      ["pdb.edge_ngram(2,5)", ParadeDB::Tokenizer.edge_ngram(2, 5)],
      ["pdb.simple", ParadeDB::Tokenizer.simple()],
      ["pdb.regex_pattern('.*')", ParadeDB::Tokenizer.regex_pattern(".*")],
      ["pdb.chinese_compatible", ParadeDB::Tokenizer.chinese_compatible()],
      ["pdb.lindera('chinese')", ParadeDB::Tokenizer.lindera("chinese")],
      ["pdb.icu", ParadeDB::Tokenizer.icu()],
      ["pdb.jieba", ParadeDB::Tokenizer.jieba()],
      ["pdb.source_code", ParadeDB::Tokenizer.source_code()]
    ].each do |expected, tokenizer|
      sql = Product.search(:description)
                   .match_all(ParadeDB.tokenize("running shoes", tokenizer))
                   .order(:id)
                   .to_sql

      assert_query_sql <<~SQL, sql
        SELECT products.* FROM products
        WHERE ("products"."description" &&& 'running shoes'::#{expected})
        ORDER BY "products"."id" ASC
      SQL
    end
  end
  it "matching all with tokenizer args" do
    sql = Product.search(:description).match_all(ParadeDB.tokenize("running shoes", ParadeDB::Tokenizer.whitespace(options: {lowercase: false}))).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" &&& 'running shoes'::pdb.whitespace('lowercase=false'))), sql
  end
  it "matching all with sql function argument" do
    term = Arel::Nodes::NamedFunction.new("lower", [Arel::Nodes.build_quoted("SHOES")])
    sql = Product.search(:description).match_all(term).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" &&& lower('SHOES'))), sql
  end
  it "excluding terms" do
    sql = Product.search(:description)
                 .match_all("shoes")
                 .excluding("cheap budget")
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes') AND (NOT ("products"."description" &&& 'cheap budget'))
    SQL

    assert_query_sql expected, sql
  end
  it "or composition" do
    base = Product.where(in_stock: true).order(id: :desc).limit(10)
    left = base.search(:description).match_all("shoes")
    right = base.search(:category).match_all("footwear")
    sql = left.or(right).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE "products"."in_stock" = TRUE AND ("products"."description" &&& 'shoes' OR "products"."category" &&& 'footwear') ORDER BY "products"."id" DESC LIMIT 10), sql
  end
  it "phrase with slop" do
    sql = Product.search(:description).phrase(ParadeDB.slop("running shoes", 2)).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" ### 'running shoes'::pdb.slop(2))), sql
  end
  it "phrase with tokenizer" do
    sql = Product.search(:description).phrase(ParadeDB.tokenize("running shoes", ParadeDB::Tokenizer.whitespace())).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" ### 'running shoes'::pdb.whitespace)), sql
  end
  it "phrase with sql function argument" do
    phrase = Arel::Nodes::NamedFunction.new("lower", [Arel::Nodes.build_quoted("RUNNING SHOES")])
    sql = Product.search(:description).phrase(phrase).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" ### lower('RUNNING SHOES'))), sql
  end
  it "phrase with pretokenized array" do
    sql = Product.search(:description).phrase(%w[running shoes]).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" ### ARRAY['running', 'shoes'])), sql
  end
  it "fuzzy with prefix" do
    sql = Product.search(:description).term(ParadeDB.fuzzy("runn", 1, prefix: true)).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" === 'runn'::pdb.fuzzy(1, "true"))), sql
  end
  it "fuzzy with prefix and boost" do
    sql = Product.search(:description).term(ParadeDB.boost(ParadeDB.fuzzy("shose", 2, prefix: false), 2)).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(2))), sql
  end
  it "regex" do
    sql = Product.search(:description).regex("run.*shoes").to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.regex('run.*shoes'))), sql
  end
  it "regex phrase" do
    sql = Product.search(:description).regex_phrase("run.*", "sho.*", slop: 2, max_expansions: 100).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.regex_phrase(ARRAY['run.*', 'sho.*'], slop => 2, max_expansions => 100))), sql
  end
  it "term exact" do
    sql = Product.search(:description).term("shoes").to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" === 'shoes')), sql
  end
  it "term set" do
    sql = Product.search(:category).term_set("audio", "footwear").to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."category" @@@ pdb.term_set(ARRAY['audio', 'footwear']))), sql
  end
  it "near proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("sleek").within(1, "shoes")).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## 'shoes'))), sql
  end
  it "near ordered proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("sleek").within(1, "shoes", ordered: true)).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ##> 1 ##> 'shoes'))), sql
  end
  it "near array proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("sleek", "white").within(1, "shoes")).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ (pdb.prox_array('sleek', 'white') ## 1 ## 'shoes'))), sql
  end
  it "near with regex wrapper" do
    sql = Product.search(:description).near(ParadeDB.regex_term("sl.*").within(1, "shoes")).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ (pdb.prox_regex('sl.*') ## 1 ## 'shoes'))), sql
  end
  it "near with mixed array left operand" do
    sql = Product.search(:description).near(ParadeDB.proximity(ParadeDB.regex_term("sl.*"), "white").within(1, "shoes")).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ (pdb.prox_array(pdb.prox_regex('sl.*'), 'white') ## 1 ## 'shoes'))), sql
  end
  it "near with array right operand" do
    sql = Product.search(:description).near(ParadeDB.proximity("sleek").within(1, "white", "shoes")).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## pdb.prox_array('white', 'shoes')))), sql
  end
  it "near left-associated chained proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("trail").within(1, "running").within(1, "shoes")).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ (('trail' ## 1 ## 'running') ## 1 ## 'shoes'))), sql
  end
  it "near right-nested chained proximity" do
    sql = Product.search(:description).near(ParadeDB.proximity("trail").within(1, ParadeDB.proximity("running").within(1, "shoes"))).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('trail' ## 1 ## ('running' ## 1 ## 'shoes')))), sql
  end
  it "near boosted proximity" do
    sql = Product.search(:description).near(ParadeDB.boost(ParadeDB.proximity("sleek").within(1, "shoes"), 2.0)).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## 'shoes')::pdb.boost(2.0))), sql
  end
  it "near constant score proximity" do
    sql = Product.search(:description).near(ParadeDB.constant(ParadeDB.proximity("sleek").within(1, "shoes"), 1.0)).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ ('sleek' ## 1 ## 'shoes')::pdb.const(1.0))), sql
  end
  it "phrase prefix" do
    sql = Product.search(:description).phrase_prefix("run", "sh").to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh']))), sql
  end
  it "phrase prefix with max expansion" do
    sql = Product.search(:description).phrase_prefix("run", "sh", max_expansion: 100).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh'], 100))), sql
  end
  it "parse query" do
    sql = Product.search(:description).parse("running AND shoes", lenient: true).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes', lenient => true))), sql
  end
  it "parse query with conjunction mode" do
    sql = Product.search(:description).parse("running shoes", conjunction_mode: true).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running shoes', conjunction_mode => true))), sql
  end
  it "parse query without options" do
    sql = Product.search(:description).parse("running AND shoes").to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes'))), sql
  end
  it "parse query with lenient false" do
    sql = Product.search(:description).parse("running AND shoes", lenient: false).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.parse('running AND shoes', lenient => false))), sql
  end
  it "match all wrapper" do
    sql = Product.search(:id).match_all.to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.all())), sql
  end
  it "exists wrapper" do
    sql = Product.search(:id).exists.to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.exists())), sql
  end
  it "range wrapper with Ruby range" do
    sql = Product.search(:rating).range(3..5).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."rating" @@@ pdb.range(int8range(3, 5, '[]')))), sql
  end
  it "range wrapper with bound options" do
    sql = Product.search(:rating).range(gte: 3, lt: 5).to_sql
    assert_query_sql %q{SELECT products.* FROM products WHERE ("products"."rating" @@@ pdb.range(int8range(3, 5, '[)')))}, sql
  end
  it "range term relation" do
    sql = Product.search(:weight_range).range_term("(10, 12]", relation: "Intersects", range_type: "int4range").to_sql
    assert_query_sql %q{SELECT products.* FROM products WHERE ("products"."weight_range" @@@ pdb.range_term('(10, 12]'::int4range, 'Intersects'))}, sql
  end
  it "range term scalar value" do
    sql = Product.search(:weight_range).range_term(1).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."weight_range" @@@ pdb.range_term(1))), sql
  end
  it "more like this" do
    sql = Product.more_like_this(3, fields: [:description]).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this(3, ARRAY['description']))), sql
  end
  it "more like this with json string" do
    sql = Product.more_like_this('{"description": "running shoes"}').to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this('{"description": "running shoes"}'))), sql
  end
  it "more like this with json hash" do
    json_doc = { description: "running shoes", category: "footwear" }.to_json
    sql = Product.more_like_this(json_doc).to_sql
    assert_query_sql %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this('{"description":"running shoes","category":"footwear"}'))), sql
  end
  it "more like this with advanced options" do
    sql = Product.more_like_this(
      5,
      fields: [:description],
      min_term_freq: 2,
      max_query_terms: 10,
      min_doc_freq: 1,
      max_doc_freq: 200,
      min_word_length: 3,
      max_word_length: 15,
      stopwords: %w[the a]
    ).to_sql

    expected = %(SELECT products.* FROM products WHERE ("products"."id" @@@ pdb.more_like_this(5, ARRAY['description'], min_term_frequency => 2, max_query_terms => 10, min_doc_frequency => 1, max_doc_frequency => 200, min_word_length => 3, max_word_length => 15, stopwords => ARRAY['the', 'a'])))
    assert_query_sql expected, sql
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
                 .match_all("running shoes")
                 .with_score
                 .order(search_score: :desc)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.score("products"."id") AS search_score FROM products
      WHERE ("products"."description" &&& 'running shoes')
      ORDER BY search_score DESC
    SQL

    assert_query_sql expected, sql
  end
  it "with snippet default" do
    sql = Product.search(:description)
                 .match_all("running shoes")
                 .with_snippet(:description)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippet("products"."description") AS description_snippet FROM products
      WHERE ("products"."description" &&& 'running shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with snippet custom" do
    sql = Product.search(:description)
                 .match_all("running shoes")
                 .with_snippet(:description, start_tag: '<mark>', end_tag: '</mark>', max_chars: 100)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippet("products"."description", '<mark>', '</mark>', 100) AS description_snippet FROM products
      WHERE ("products"."description" &&& 'running shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with snippets custom options" do
    sql = Product.search(:description)
                 .match_all("running shoes")
                 .with_snippets(:description, max_chars: 15, limit: 1, offset: 0, sort_by: :position)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippets("products"."description", max_num_chars => 15, "limit" => 1, "offset" => 0, sort_by => 'position') AS description_snippets FROM products
      WHERE ("products"."description" &&& 'running shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with snippet positions" do
    sql = Product.search(:description)
                 .match_all("running shoes")
                 .with_snippet_positions(:description)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippet_positions("products"."description") AS description_snippet_positions FROM products
      WHERE ("products"."description" &&& 'running shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with score then with snippet keeps both projections" do
    sql = Product.search(:description)
                 .match_all("shoes")
                 .with_score
                 .with_snippet(:description)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.score("products"."id") AS search_score, pdb.snippet("products"."description") AS description_snippet FROM products
      WHERE ("products"."description" &&& 'shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with snippet then with score keeps both projections" do
    sql = Product.search(:description)
                 .match_all("shoes")
                 .with_snippet(:description)
                 .with_score
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.snippet("products"."description") AS description_snippet, pdb.score("products"."id") AS search_score FROM products
      WHERE ("products"."description" &&& 'shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with snippets custom alias" do
    sql = Product.search(:description).match_all("shoes")
                     .with_snippets(:description, as: :all_snips)
                     .to_sql

    assert_query_sql %(SELECT products.*, pdb.snippets("products"."description") AS all_snips FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "with snippet positions custom alias" do
    sql = Product.search(:description).match_all("shoes")
                     .with_snippet_positions(:description, as: "positions")
                     .to_sql

    assert_query_sql %(SELECT products.*, pdb.snippet_positions("products"."description") AS positions FROM products
      WHERE ("products"."description" &&& 'shoes')), sql
  end
  it "facets only" do
    facet_sql = Product.search(:description).match_all("shoes")
                       .build_facet_query(fields: [:category, :brand], size: 10, order: :count_desc)
                       .sql

    expected = %(SELECT pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') AS category_facet, pdb.agg('{"terms":{"field":"brand","size":10,"order":{"_count":"desc"}}}') AS brand_facet FROM (SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes')) paradedb_facet_source)

    assert_query_sql expected, facet_sql
  end
  it "with facets rows plus facets" do
    sql = Product.search(:description).match_all("shoes")
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

    assert_query_sql expected, sql
  end
  it "facets with custom agg without fields still projects aggregate" do
    facet_sql = Product.search(:description).match_all("shoes")
                           .build_facet_query(
                             fields: [],
                             size: 99,
                             order: :count_asc,
                             missing: "(missing)",
                             agg: { "value_count" => { "field" => "id" } }
                           )
                           .sql

    assert_query_sql %(SELECT pdb.agg('{"value_count":{"field":"id"}}') AS agg_facet FROM (SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes')) paradedb_facet_source), facet_sql
  end
  it "facets without paradedb predicates" do
    facet_sql = Product.where(in_stock: true)
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    expected = %(SELECT pdb.agg('{\"terms\":{\"field\":\"category\",\"size\":10}}') AS category_facet FROM (SELECT products.* FROM products WHERE \"products\".\"in_stock\" = TRUE AND (\"products\".\"id\" @@@ pdb.all())) paradedb_facet_source)

    assert_query_sql expected, facet_sql
  end
  it "facets with size nil omits size clause" do
    facet_sql = Product.search(:description).match_all("shoes")
                           .build_facet_query(fields: [:category], size: nil, order: nil)
                           .sql

    expected = %(SELECT pdb.agg('{"terms":{"field":"category"}}') AS category_facet FROM (SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes')) paradedb_facet_source)
    assert_query_sql expected, facet_sql
  end
  it "facets with raw paradedb sql predicate does not append match all" do
    facet_sql = Product.where(Arel.sql(%("products"."description" @@@ pdb.regex('run.*'))))
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_query_sql %(SELECT pdb.agg('{"terms":{"field":"category","size":10}}') AS category_facet FROM (SELECT products.* FROM products WHERE ("products"."description" @@@ pdb.regex('run.*'))) paradedb_facet_source), facet_sql
  end
  it "facets with non paradedb sql predicate appends match all" do
    facet_sql = Product.where(Arel.sql(%("products"."price" > 50)))
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_query_sql %(SELECT pdb.agg('{"terms":{"field":"category","size":10}}') AS category_facet FROM (SELECT products.* FROM products WHERE ("products"."price" > 50) AND ("products"."id" @@@ pdb.all())) paradedb_facet_source), facet_sql
  end
  it "facets with mixed paradedb and standard predicates keeps existing paradedb predicate" do
    facet_sql = Product.where(in_stock: true)
                           .search(:description)
                           .match_all("shoes")
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_query_sql %(SELECT pdb.agg('{"terms":{"field":"category","size":10}}') AS category_facet FROM (SELECT products.* FROM products WHERE "products"."in_stock" = TRUE AND ("products"."description" &&& 'shoes')) paradedb_facet_source), facet_sql
  end
  it "with facets without paradedb predicates" do
    sql = Product.where(in_stock: true)
                     .extending(ParadeDB::SearchMethods)
                     .with_facets(:category, size: 10)
                     .order(:id)
                     .limit(10)
                     .to_sql

    expected = <<~SQL.strip
      SELECT products.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') OVER () AS _category_facet FROM products
      WHERE "products"."in_stock" = TRUE AND ("products"."id" @@@ pdb.all())
      ORDER BY "products"."id" ASC
      LIMIT 10
    SQL

    assert_query_sql expected, sql
  end
  it "with facets default order is desc count" do
    sql = Product.search(:description)
                     .match_all("shoes")
                     .with_facets(:category, size: 10)
                     .order(:id)
                     .limit(10)
                     .to_sql

    expected = %(SELECT products.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') OVER () AS _category_facet FROM products WHERE ("products"."description" &&& 'shoes') ORDER BY "products"."id" ASC LIMIT 10)
    assert_query_sql expected, sql
  end
  it "with facets exact false emits second agg argument" do
    sql = Product.search(:description)
                     .match_all("shoes")
                     .with_facets(:category, size: 10, exact: false)
                     .order(:id)
                     .limit(10)
                     .to_sql

    expected = %(SELECT products.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}', false) OVER () AS _category_facet FROM products WHERE ("products"."description" &&& 'shoes') ORDER BY "products"."id" ASC LIMIT 10)
    assert_query_sql expected, sql
  end
  it "facets exact false raises" do
    error = assert_raises(ArgumentError) do
      Product.search(:description).match_all("shoes").facets(:category, exact: false)
    end
    assert_includes error.message, "facets(exact: false)"
  end
  it "with facets uses custom agg and ignores field size order missing" do
    sql = Product.search(:description)
                     .match_all("shoes")
                     .with_facets(
                       :category,
                       size: 20,
                       order: :count_desc,
                       missing: "(missing)",
                       agg: { "value_count" => { "field" => "id" } }
                     )
                     .order(:id)
                     .limit(10)
                     .to_sql

    assert_query_sql %(SELECT products.*, pdb.agg('{"value_count":{"field":"id"}}') OVER () AS _agg_facet FROM products WHERE ("products"."description" &&& 'shoes') ORDER BY "products"."id" ASC LIMIT 10), sql
  end
  it "facets_agg builds one pdb.agg projection per named aggregation" do
    facet_sql = Product.search(:description)
                           .match_all("shoes")
                           .send(
                             :build_aggregation_query,
                             Product.search(:description)
                                        .match_all("shoes")
                                        .send(
                                          :normalize_named_aggregation_specs,
                                          docs: ParadeDB::Aggregations.value_count(:id),
                                          avg_rating: ParadeDB::Aggregations.avg(:rating)
                                        )
                           )
                           .sql

    assert_query_sql %(SELECT pdb.agg('{"value_count":{"field":"id"}}') AS docs_facet, pdb.agg('{"avg":{"field":"rating"}}') AS avg_rating_facet FROM (SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes')) paradedb_agg_source), facet_sql
  end
  it "with_agg adds multiple window aggregates" do
    sql = Product.search(:description)
                     .match_all("shoes")
                     .with_agg(
                       docs: ParadeDB::Aggregations.value_count(:id),
                       avg_rating: ParadeDB::Aggregations.avg(:rating)
                     )
                     .order(:id)
                     .limit(10)
                     .to_sql

    assert_query_sql %(SELECT products.*, pdb.agg('{"value_count":{"field":"id"}}') OVER () AS _docs_facet, pdb.agg('{"avg":{"field":"rating"}}') OVER () AS _avg_rating_facet FROM products WHERE ("products"."description" &&& 'shoes') ORDER BY "products"."id" ASC LIMIT 10), sql
  end
  it "with_agg exact false emits second agg argument" do
    sql = Product.search(:description)
                     .match_all("shoes")
                     .with_agg(
                       exact: false,
                       docs: ParadeDB::Aggregations.value_count(:id)
                     )
                     .order(:id)
                     .limit(10)
                     .to_sql

    assert_query_sql %(SELECT products.*, pdb.agg('{"value_count":{"field":"id"}}', false) OVER () AS _docs_facet FROM products WHERE ("products"."description" &&& 'shoes') ORDER BY "products"."id" ASC LIMIT 10), sql
  end
  it "with_agg supports filtered named aggregations" do
    sql = Product.with_agg(
      electronics_count: ParadeDB::Aggregations.filtered(
        ParadeDB::Aggregations.value_count(:id),
        field: :category,
        term: "electronics"
      )
    ).order(:id).limit(10).to_sql

    assert_sql_equal %(SELECT products.*, pdb.agg('{"value_count":{"field":"id"}}') FILTER (WHERE "products"."category" === 'electronics') OVER () AS _electronics_count_facet FROM products WHERE ("products"."id" @@@ pdb.all()) ORDER BY "products"."id" ASC LIMIT 10), sql
  end
  it "facets_agg supports filtered named aggregations" do
    facet_sql = Product.search(:description)
                           .match_all("shoes")
                           .send(
                             :build_aggregation_query,
                             Product.search(:description)
                                        .match_all("shoes")
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

    assert_query_sql %(SELECT pdb.agg('{"value_count":{"field":"id"}}') FILTER (WHERE "paradedb_agg_source"."category" === 'electronics') AS electronics_count_facet FROM (SELECT products.* FROM products WHERE ("products"."description" &&& 'shoes')) paradedb_agg_source), facet_sql
  end
  it "model with_agg class helper delegates to relation api" do
    sql = Product.with_agg(docs: ParadeDB::Aggregations.value_count(:id)).order(:id).limit(10).to_sql

    assert_query_sql %(SELECT products.*, pdb.agg('{"value_count":{"field":"id"}}') OVER () AS _docs_facet FROM products WHERE ("products"."id" @@@ pdb.all()) ORDER BY "products"."id" ASC LIMIT 10), sql
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

    assert_query_sql expected, sql
  end
  it "model aggregate_by adds match all when no paradedb predicate exists" do
    sql = Product.aggregate_by(:rating, agg: ParadeDB::Aggregations.value_count(:id)).to_sql

    assert_query_sql %(SELECT "products"."rating", pdb.agg('{"value_count":{"field":"id"}}') AS agg FROM "products" WHERE ("products"."id" @@@ pdb.all()) GROUP BY "products"."rating"), sql
  end
  it "with facets load requires order and limit" do
    rel = Product.search(:description)
                     .match_all("shoes")
                     .with_facets(:category, size: 10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY and LIMIT"
  end
  it "with facets load requires limit" do
    rel = Product.search(:description)
                     .match_all("shoes")
                     .with_facets(:category, size: 10)
                     .order(:id)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "LIMIT"
  end
  it "with facets load requires order" do
    rel = Product.search(:description)
                     .match_all("shoes")
                     .with_facets(:category, size: 10)
                     .limit(10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY"
  end

  it "nearest adds match-all predicate and distance ordering" do
    sql = Product.nearest(:embedding, [1, 2, 3]).limit(2).to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."id" @@@ pdb.all())
      ORDER BY "products"."embedding" <-> '[1.0,2.0,3.0]'::vector ASC
      LIMIT 2
    SQL

    assert_query_sql expected, sql
  end
  it "nearest respects an explicit metric" do
    sql = Product.nearest(:embedding, [1, 2, 3], metric: :ip).limit(2).to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."id" @@@ pdb.all())
      ORDER BY "products"."embedding" <#> '[1.0,2.0,3.0]'::vector ASC
      LIMIT 2
    SQL

    assert_query_sql expected, sql
  end
  it "nearest defaults the metric from the index definition" do
    sql = VectorIndexedProduct.nearest(:embedding, [1, 2, 3]).limit(2).to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."id" @@@ pdb.all())
      ORDER BY "products"."embedding" <=> '[1.0,2.0,3.0]'::vector ASC
      LIMIT 2
    SQL

    assert_query_sql expected, sql
  end
  it "nearest preserves existing paradedb predicates" do
    sql = Product.search(:description)
                 .match_all("shoes")
                 .nearest(:embedding, [1, 2, 3], metric: :l2)
                 .limit(2)
                 .to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE ("products"."description" &&& 'shoes')
      ORDER BY "products"."embedding" <-> '[1.0,2.0,3.0]'::vector ASC
      LIMIT 2
    SQL

    assert_query_sql expected, sql
  end
  it "nearest chains with standard relation filters" do
    sql = Product.where(in_stock: true).extending(ParadeDB::SearchMethods)
                 .nearest(:embedding, [1, 2, 3]).limit(5).to_sql

    expected = <<~SQL.strip
      SELECT products.* FROM products
      WHERE "products"."in_stock" = true
        AND ("products"."id" @@@ pdb.all())
      ORDER BY "products"."embedding" <-> '[1.0,2.0,3.0]'::vector ASC
      LIMIT 5
    SQL

    assert_query_sql expected, sql
  end
  it "builds metric-specific vector distance expressions" do
    assert_query_sql %(SELECT "products"."embedding" <-> '[1.0,2.0,3.0]'::vector AS distance FROM "products"), Product.select(Product.l2_distance(:embedding, [1, 2, 3]).as("distance")).to_sql
    assert_query_sql %(SELECT "products"."embedding" <=> '[1.0,2.0,3.0]'::vector AS distance FROM "products"), Product.select(Product.cosine_distance(:embedding, [1, 2, 3]).as("distance")).to_sql
    assert_query_sql %(SELECT "products"."embedding" <#> '[1.0,2.0,3.0]'::vector AS distance FROM "products"), Product.select(Product.inner_product(:embedding, [1, 2, 3]).as("distance")).to_sql
  end
end
