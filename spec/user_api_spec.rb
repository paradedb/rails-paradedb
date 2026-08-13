# frozen_string_literal: true

require "spec_helper"

class MockItem < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :mock_items
end

class VectorIndexedMockItemIndex < ParadeDB::Index
  self.table_name = :mock_items
  self.key_field = :id
  self.index_name = :mock_items_vector_search_idx
  self.fields = {
    id: {},
    description: nil,
    embedding: { metric: :cosine }
  }
end

class VectorIndexedMockItem < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :mock_items

  paradedb_index VectorIndexedMockItemIndex
end

RSpec.describe "UserApi" do
  before(:context) { setup_test_index }

  it "matching all with filters" do
    sql = MockItem.search(:description)
                 .match_all("running shoes")
                 .where(in_stock: true)
                 .where("mock_items.created_at IS NOT NULL")
                 .where(rating: 4..)
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.* FROM mock_items
      WHERE ("mock_items"."description" &&& 'running shoes')
        AND "mock_items"."in_stock" = true
        AND (mock_items.created_at IS NOT NULL)
        AND "mock_items"."rating" >= 4
    SQL

    assert_query_sql expected, sql
  end
  it "chain multiple search fields and" do
    sql = MockItem.search(:description).match_all("running shoes")
                 .search(:category).phrase("Footwear")
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.* FROM mock_items
      WHERE ("mock_items"."description" &&& 'running shoes') AND ("mock_items"."category" ### 'Footwear')
    SQL

    assert_query_sql expected, sql
  end
  it "matching any or semantics" do
    sql = MockItem.search(:description).match_any("wireless bluetooth").to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" ||| 'wireless bluetooth')), sql
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
      sql = MockItem.search(:description)
                   .match_all(ParadeDB.tokenize("running shoes", tokenizer))
                   .order(:id)
                   .to_sql

      assert_query_sql <<~SQL, sql
        SELECT mock_items.* FROM mock_items
        WHERE ("mock_items"."description" &&& 'running shoes'::#{expected})
        ORDER BY "mock_items"."id" ASC
      SQL
    end
  end
  it "matching all with tokenizer args" do
    sql = MockItem.search(:description).match_all(ParadeDB.tokenize("running shoes", ParadeDB::Tokenizer.whitespace(options: {lowercase: false}))).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" &&& 'running shoes'::pdb.whitespace('lowercase=false'))), sql
  end
  it "matching all with sql function argument" do
    term = Arel::Nodes::NamedFunction.new("lower", [Arel::Nodes.build_quoted("SHOES")])
    sql = MockItem.search(:description).match_all(term).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" &&& lower('SHOES'))), sql
  end
  it "excluding terms" do
    sql = MockItem.search(:description)
                 .match_all("shoes")
                 .excluding("cheap budget")
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.* FROM mock_items
      WHERE ("mock_items"."description" &&& 'shoes') AND (NOT ("mock_items"."description" &&& 'cheap budget'))
    SQL

    assert_query_sql expected, sql
  end
  it "or composition" do
    base = MockItem.where(in_stock: true).order(id: :desc).limit(10)
    left = base.search(:description).match_all("shoes")
    right = base.search(:category).match_all("footwear")
    sql = left.or(right).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE "mock_items"."in_stock" = TRUE AND ("mock_items"."description" &&& 'shoes' OR "mock_items"."category" &&& 'footwear') ORDER BY "mock_items"."id" DESC LIMIT 10), sql
  end
  it "phrase with slop" do
    sql = MockItem.search(:description).phrase(ParadeDB.slop("running shoes", 2)).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" ### 'running shoes'::pdb.slop(2))), sql
  end
  it "phrase with tokenizer" do
    sql = MockItem.search(:description).phrase(ParadeDB.tokenize("running shoes", ParadeDB::Tokenizer.whitespace())).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" ### 'running shoes'::pdb.whitespace)), sql
  end
  it "phrase with sql function argument" do
    phrase = Arel::Nodes::NamedFunction.new("lower", [Arel::Nodes.build_quoted("RUNNING SHOES")])
    sql = MockItem.search(:description).phrase(phrase).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" ### lower('RUNNING SHOES'))), sql
  end
  it "phrase with pretokenized array" do
    sql = MockItem.search(:description).phrase(%w[running shoes]).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" ### ARRAY['running', 'shoes'])), sql
  end
  it "fuzzy with prefix" do
    sql = MockItem.search(:description).term(ParadeDB.fuzzy("runn", 1, prefix: true)).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" === 'runn'::pdb.fuzzy(1, "true"))), sql
  end
  it "fuzzy with prefix and boost" do
    sql = MockItem.search(:description).term(ParadeDB.boost(ParadeDB.fuzzy("shose", 2, prefix: false), 2)).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(2))), sql
  end
  it "regex" do
    sql = MockItem.search(:description).regex("run.*shoes").to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ pdb.regex('run.*shoes'))), sql
  end
  it "regex phrase" do
    sql = MockItem.search(:description).regex_phrase("run.*", "sho.*", slop: 2, max_expansions: 100).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ pdb.regex_phrase(ARRAY['run.*', 'sho.*'], slop => 2, max_expansions => 100))), sql
  end
  it "term exact" do
    sql = MockItem.search(:description).term("shoes").to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" === 'shoes')), sql
  end
  it "term set" do
    sql = MockItem.search(:category).term_set("audio", "footwear").to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."category" @@@ pdb.term_set(ARRAY['audio', 'footwear']))), sql
  end
  it "near proximity" do
    sql = MockItem.search(:description).near(ParadeDB.proximity("sleek").within(1, "shoes")).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ ('sleek' ## 1 ## 'shoes'))), sql
  end
  it "near ordered proximity" do
    sql = MockItem.search(:description).near(ParadeDB.proximity("sleek").within(1, "shoes", ordered: true)).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ ('sleek' ##> 1 ##> 'shoes'))), sql
  end
  it "near array proximity" do
    sql = MockItem.search(:description).near(ParadeDB.proximity("sleek", "white").within(1, "shoes")).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ (pdb.prox_array('sleek', 'white') ## 1 ## 'shoes'))), sql
  end
  it "near with regex wrapper" do
    sql = MockItem.search(:description).near(ParadeDB.regex_term("sl.*").within(1, "shoes")).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ (pdb.prox_regex('sl.*') ## 1 ## 'shoes'))), sql
  end
  it "near with mixed array left operand" do
    sql = MockItem.search(:description).near(ParadeDB.proximity(ParadeDB.regex_term("sl.*"), "white").within(1, "shoes")).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ (pdb.prox_array(pdb.prox_regex('sl.*'), 'white') ## 1 ## 'shoes'))), sql
  end
  it "near with array right operand" do
    sql = MockItem.search(:description).near(ParadeDB.proximity("sleek").within(1, "white", "shoes")).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ ('sleek' ## 1 ## pdb.prox_array('white', 'shoes')))), sql
  end
  it "near left-associated chained proximity" do
    sql = MockItem.search(:description).near(ParadeDB.proximity("trail").within(1, "running").within(1, "shoes")).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ (('trail' ## 1 ## 'running') ## 1 ## 'shoes'))), sql
  end
  it "near right-nested chained proximity" do
    sql = MockItem.search(:description).near(ParadeDB.proximity("trail").within(1, ParadeDB.proximity("running").within(1, "shoes"))).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ ('trail' ## 1 ## ('running' ## 1 ## 'shoes')))), sql
  end
  it "near boosted proximity" do
    sql = MockItem.search(:description).near(ParadeDB.boost(ParadeDB.proximity("sleek").within(1, "shoes"), 2.0)).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ ('sleek' ## 1 ## 'shoes')::pdb.boost(2.0))), sql
  end
  it "near constant score proximity" do
    sql = MockItem.search(:description).near(ParadeDB.constant(ParadeDB.proximity("sleek").within(1, "shoes"), 1.0)).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ ('sleek' ## 1 ## 'shoes')::pdb.const(1.0))), sql
  end
  it "phrase prefix" do
    sql = MockItem.search(:description).phrase_prefix("run", "sh").to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh']))), sql
  end
  it "phrase prefix with max expansion" do
    sql = MockItem.search(:description).phrase_prefix("run", "sh", max_expansion: 100).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh'], 100))), sql
  end
  it "parse query" do
    sql = MockItem.search(:description).parse("running AND shoes", lenient: true).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ pdb.parse('running AND shoes', lenient => true))), sql
  end
  it "parse query with conjunction mode" do
    sql = MockItem.search(:description).parse("running shoes", conjunction_mode: true).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ pdb.parse('running shoes', conjunction_mode => true))), sql
  end
  it "parse query without options" do
    sql = MockItem.search(:description).parse("running AND shoes").to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ pdb.parse('running AND shoes'))), sql
  end
  it "parse query with lenient false" do
    sql = MockItem.search(:description).parse("running AND shoes", lenient: false).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ pdb.parse('running AND shoes', lenient => false))), sql
  end
  it "match all wrapper" do
    sql = MockItem.search(:id).match_all.to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."id" @@@ pdb.all())), sql
  end
  it "exists wrapper" do
    sql = MockItem.search(:id).exists.to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."id" @@@ pdb.exists())), sql
  end
  it "range wrapper with Ruby range" do
    sql = MockItem.search(:rating).range(3..5).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."rating" @@@ pdb.range(int8range(3, 5, '[]')))), sql
  end
  it "range wrapper with bound options" do
    sql = MockItem.search(:rating).range(gte: 3, lt: 5).to_sql
    assert_query_sql %q{SELECT mock_items.* FROM mock_items WHERE ("mock_items"."rating" @@@ pdb.range(int8range(3, 5, '[)')))}, sql
  end
  it "range term relation" do
    sql = MockItem.search(:weight_range).range_term("(10, 12]", relation: "Intersects", range_type: "int4range").to_sql
    assert_query_sql %q{SELECT mock_items.* FROM mock_items WHERE ("mock_items"."weight_range" @@@ pdb.range_term('(10, 12]'::int4range, 'Intersects'))}, sql
  end
  it "range term scalar value" do
    sql = MockItem.search(:weight_range).range_term(1).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."weight_range" @@@ pdb.range_term(1))), sql
  end
  it "more like this" do
    sql = MockItem.more_like_this(3, fields: [:description]).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."id" @@@ pdb.more_like_this(3, ARRAY['description']))), sql
  end
  it "more like this with json string" do
    sql = MockItem.more_like_this('{"description": "running shoes"}').to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."id" @@@ pdb.more_like_this('{"description": "running shoes"}'))), sql
  end
  it "more like this with json hash" do
    json_doc = { description: "running shoes", category: "footwear" }.to_json
    sql = MockItem.more_like_this(json_doc).to_sql
    assert_query_sql %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."id" @@@ pdb.more_like_this('{"description":"running shoes","category":"footwear"}'))), sql
  end
  it "more like this with advanced options" do
    sql = MockItem.more_like_this(
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

    expected = %(SELECT mock_items.* FROM mock_items WHERE ("mock_items"."id" @@@ pdb.more_like_this(5, ARRAY['description'], min_term_frequency => 2, max_query_terms => 10, min_doc_frequency => 1, max_doc_frequency => 200, min_word_length => 3, max_word_length => 15, stopwords => ARRAY['the', 'a'])))
    assert_query_sql expected, sql
  end
  it "more like this key extraction does not fallback to id for non-id key fields" do
    relation = MockItem.all.extending(ParadeDB::SearchMethods)
    key = Struct.new(:id).new(42)

    error = assert_raises(ArgumentError) { relation.send(:more_like_this_key_value, key, :external_id) }
    assert_includes error.message, "external_id"
    assert_equal 42, relation.send(:more_like_this_key_value, key, :id)
  end
  it "with score and order" do
    sql = MockItem.search(:description)
                 .match_all("running shoes")
                 .with_score
                 .order(search_score: :desc)
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.*, pdb.score("mock_items"."id") AS search_score FROM mock_items
      WHERE ("mock_items"."description" &&& 'running shoes')
      ORDER BY search_score DESC
    SQL

    assert_query_sql expected, sql
  end
  it "with snippet default" do
    sql = MockItem.search(:description)
                 .match_all("running shoes")
                 .with_snippet(:description)
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.*, pdb.snippet("mock_items"."description") AS description_snippet FROM mock_items
      WHERE ("mock_items"."description" &&& 'running shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with snippet custom" do
    sql = MockItem.search(:description)
                 .match_all("running shoes")
                 .with_snippet(:description, start_tag: '<mark>', end_tag: '</mark>', max_chars: 100)
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.*, pdb.snippet("mock_items"."description", '<mark>', '</mark>', 100) AS description_snippet FROM mock_items
      WHERE ("mock_items"."description" &&& 'running shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with snippets custom options" do
    sql = MockItem.search(:description)
                 .match_all("running shoes")
                 .with_snippets(:description, max_chars: 15, limit: 1, offset: 0, sort_by: :position)
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.*, pdb.snippets("mock_items"."description", max_num_chars => 15, "limit" => 1, "offset" => 0, sort_by => 'position') AS description_snippets FROM mock_items
      WHERE ("mock_items"."description" &&& 'running shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with snippet positions" do
    sql = MockItem.search(:description)
                 .match_all("running shoes")
                 .with_snippet_positions(:description)
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.*, pdb.snippet_positions("mock_items"."description") AS description_snippet_positions FROM mock_items
      WHERE ("mock_items"."description" &&& 'running shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with score then with snippet keeps both projections" do
    sql = MockItem.search(:description)
                 .match_all("shoes")
                 .with_score
                 .with_snippet(:description)
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.*, pdb.score("mock_items"."id") AS search_score, pdb.snippet("mock_items"."description") AS description_snippet FROM mock_items
      WHERE ("mock_items"."description" &&& 'shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with snippet then with score keeps both projections" do
    sql = MockItem.search(:description)
                 .match_all("shoes")
                 .with_snippet(:description)
                 .with_score
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.*, pdb.snippet("mock_items"."description") AS description_snippet, pdb.score("mock_items"."id") AS search_score FROM mock_items
      WHERE ("mock_items"."description" &&& 'shoes')
    SQL

    assert_query_sql expected, sql
  end
  it "with snippets custom alias" do
    sql = MockItem.search(:description).match_all("shoes")
                     .with_snippets(:description, as: :all_snips)
                     .to_sql

    assert_query_sql %(SELECT mock_items.*, pdb.snippets("mock_items"."description") AS all_snips FROM mock_items
      WHERE ("mock_items"."description" &&& 'shoes')), sql
  end
  it "with snippet positions custom alias" do
    sql = MockItem.search(:description).match_all("shoes")
                     .with_snippet_positions(:description, as: "positions")
                     .to_sql

    assert_query_sql %(SELECT mock_items.*, pdb.snippet_positions("mock_items"."description") AS positions FROM mock_items
      WHERE ("mock_items"."description" &&& 'shoes')), sql
  end
  it "facets only" do
    facet_sql = MockItem.search(:description).match_all("shoes")
                       .build_facet_query(fields: [:category, :rating], size: 10, order: :count_desc)
                       .sql

    expected = %(SELECT pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') AS category_facet, pdb.agg('{"terms":{"field":"rating","size":10,"order":{"_count":"desc"}}}') AS rating_facet FROM (SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" &&& 'shoes')) paradedb_facet_source)

    assert_query_sql expected, facet_sql
  end
  it "with facets rows plus facets" do
    sql = MockItem.search(:description).match_all("shoes")
                 .where(in_stock: true)
                 .with_facets(:category, :rating, size: 10)
                 .order(rating: :desc)
                 .limit(10)
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') OVER () AS _category_facet, pdb.agg('{"terms":{"field":"rating","size":10,"order":{"_count":"desc"}}}') OVER () AS _rating_facet FROM mock_items
      WHERE ("mock_items"."description" &&& 'shoes') AND "mock_items"."in_stock" = true
      ORDER BY "mock_items"."rating" DESC
      LIMIT 10
    SQL

    assert_query_sql expected, sql
  end
  it "facets with custom agg without fields still projects aggregate" do
    facet_sql = MockItem.search(:description).match_all("shoes")
                           .build_facet_query(
                             fields: [],
                             size: 99,
                             order: :count_asc,
                             missing: "(missing)",
                             agg: { "value_count" => { "field" => "id" } }
                           )
                           .sql

    assert_query_sql %(SELECT pdb.agg('{"value_count":{"field":"id"}}') AS agg_facet FROM (SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" &&& 'shoes')) paradedb_facet_source), facet_sql
  end
  it "facets without paradedb predicates" do
    facet_sql = MockItem.where(in_stock: true)
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    expected = %(SELECT pdb.agg('{\"terms\":{\"field\":\"category\",\"size\":10}}') AS category_facet FROM (SELECT mock_items.* FROM mock_items WHERE \"mock_items\".\"in_stock\" = TRUE AND (\"mock_items\".\"id\" @@@ pdb.all())) paradedb_facet_source)

    assert_query_sql expected, facet_sql
  end
  it "facets with size nil omits size clause" do
    facet_sql = MockItem.search(:description).match_all("shoes")
                           .build_facet_query(fields: [:category], size: nil, order: nil)
                           .sql

    expected = %(SELECT pdb.agg('{"terms":{"field":"category"}}') AS category_facet FROM (SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" &&& 'shoes')) paradedb_facet_source)
    assert_query_sql expected, facet_sql
  end
  it "facets with raw paradedb sql predicate does not append match all" do
    facet_sql = MockItem.where(Arel.sql(%("mock_items"."description" @@@ pdb.regex('run.*'))))
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_query_sql %(SELECT pdb.agg('{"terms":{"field":"category","size":10}}') AS category_facet FROM (SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" @@@ pdb.regex('run.*'))) paradedb_facet_source), facet_sql
  end
  it "facets with non paradedb sql predicate appends match all" do
    facet_sql = MockItem.where(Arel.sql(%("mock_items"."rating" > 3)))
                           .extending(ParadeDB::SearchMethods)
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_query_sql %(SELECT pdb.agg('{"terms":{"field":"category","size":10}}') AS category_facet FROM (SELECT mock_items.* FROM mock_items WHERE ("mock_items"."rating" > 3) AND ("mock_items"."id" @@@ pdb.all())) paradedb_facet_source), facet_sql
  end
  it "facets with mixed paradedb and standard predicates keeps existing paradedb predicate" do
    facet_sql = MockItem.where(in_stock: true)
                           .search(:description)
                           .match_all("shoes")
                           .build_facet_query(fields: [:category], size: 10, order: nil)
                           .sql

    assert_query_sql %(SELECT pdb.agg('{"terms":{"field":"category","size":10}}') AS category_facet FROM (SELECT mock_items.* FROM mock_items WHERE "mock_items"."in_stock" = TRUE AND ("mock_items"."description" &&& 'shoes')) paradedb_facet_source), facet_sql
  end
  it "with facets without paradedb predicates" do
    sql = MockItem.where(in_stock: true)
                     .extending(ParadeDB::SearchMethods)
                     .with_facets(:category, size: 10)
                     .order(:id)
                     .limit(10)
                     .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') OVER () AS _category_facet FROM mock_items
      WHERE "mock_items"."in_stock" = TRUE AND ("mock_items"."id" @@@ pdb.all())
      ORDER BY "mock_items"."id" ASC
      LIMIT 10
    SQL

    assert_query_sql expected, sql
  end
  it "with facets default order is desc count" do
    sql = MockItem.search(:description)
                     .match_all("shoes")
                     .with_facets(:category, size: 10)
                     .order(:id)
                     .limit(10)
                     .to_sql

    expected = %(SELECT mock_items.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}') OVER () AS _category_facet FROM mock_items WHERE ("mock_items"."description" &&& 'shoes') ORDER BY "mock_items"."id" ASC LIMIT 10)
    assert_query_sql expected, sql
  end
  it "with facets exact false emits second agg argument" do
    sql = MockItem.search(:description)
                     .match_all("shoes")
                     .with_facets(:category, size: 10, exact: false)
                     .order(:id)
                     .limit(10)
                     .to_sql

    expected = %(SELECT mock_items.*, pdb.agg('{"terms":{"field":"category","size":10,"order":{"_count":"desc"}}}', false) OVER () AS _category_facet FROM mock_items WHERE ("mock_items"."description" &&& 'shoes') ORDER BY "mock_items"."id" ASC LIMIT 10)
    assert_query_sql expected, sql
  end
  it "facets exact false raises" do
    error = assert_raises(ArgumentError) do
      MockItem.search(:description).match_all("shoes").facets(:category, exact: false)
    end
    assert_includes error.message, "facets(exact: false)"
  end
  it "with facets uses custom agg and ignores field size order missing" do
    sql = MockItem.search(:description)
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

    assert_query_sql %(SELECT mock_items.*, pdb.agg('{"value_count":{"field":"id"}}') OVER () AS _agg_facet FROM mock_items WHERE ("mock_items"."description" &&& 'shoes') ORDER BY "mock_items"."id" ASC LIMIT 10), sql
  end
  it "facets_agg builds one pdb.agg projection per named aggregation" do
    facet_sql = MockItem.search(:description)
                           .match_all("shoes")
                           .send(
                             :build_aggregation_query,
                             MockItem.search(:description)
                                        .match_all("shoes")
                                        .send(
                                          :normalize_named_aggregation_specs,
                                          docs: ParadeDB::Aggregations.value_count(:id),
                                          avg_rating: ParadeDB::Aggregations.avg(:rating)
                                        )
                           )
                           .sql

    assert_query_sql %(SELECT pdb.agg('{"value_count":{"field":"id"}}') AS docs_facet, pdb.agg('{"avg":{"field":"rating"}}') AS avg_rating_facet FROM (SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" &&& 'shoes')) paradedb_agg_source), facet_sql
  end
  it "with_agg adds multiple window aggregates" do
    sql = MockItem.search(:description)
                     .match_all("shoes")
                     .with_agg(
                       docs: ParadeDB::Aggregations.value_count(:id),
                       avg_rating: ParadeDB::Aggregations.avg(:rating)
                     )
                     .order(:id)
                     .limit(10)
                     .to_sql

    assert_query_sql %(SELECT mock_items.*, pdb.agg('{"value_count":{"field":"id"}}') OVER () AS _docs_facet, pdb.agg('{"avg":{"field":"rating"}}') OVER () AS _avg_rating_facet FROM mock_items WHERE ("mock_items"."description" &&& 'shoes') ORDER BY "mock_items"."id" ASC LIMIT 10), sql
  end
  it "with_agg exact false emits second agg argument" do
    sql = MockItem.search(:description)
                     .match_all("shoes")
                     .with_agg(
                       exact: false,
                       docs: ParadeDB::Aggregations.value_count(:id)
                     )
                     .order(:id)
                     .limit(10)
                     .to_sql

    assert_query_sql %(SELECT mock_items.*, pdb.agg('{"value_count":{"field":"id"}}', false) OVER () AS _docs_facet FROM mock_items WHERE ("mock_items"."description" &&& 'shoes') ORDER BY "mock_items"."id" ASC LIMIT 10), sql
  end
  it "with_agg supports filtered named aggregations" do
    sql = MockItem.with_agg(
      electronics_count: ParadeDB::Aggregations.filtered(
        ParadeDB::Aggregations.value_count(:id),
        field: :category,
        term: "electronics"
      )
    ).order(:id).limit(10).to_sql

    assert_sql_equal %(SELECT mock_items.*, pdb.agg('{"value_count":{"field":"id"}}') FILTER (WHERE "mock_items"."category" === 'electronics') OVER () AS _electronics_count_facet FROM mock_items WHERE ("mock_items"."id" @@@ pdb.all()) ORDER BY "mock_items"."id" ASC LIMIT 10), sql
  end
  it "facets_agg supports filtered named aggregations" do
    facet_sql = MockItem.search(:description)
                           .match_all("shoes")
                           .send(
                             :build_aggregation_query,
                             MockItem.search(:description)
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

    assert_query_sql %(SELECT pdb.agg('{"value_count":{"field":"id"}}') FILTER (WHERE "paradedb_agg_source"."category" === 'electronics') AS electronics_count_facet FROM (SELECT mock_items.* FROM mock_items WHERE ("mock_items"."description" &&& 'shoes')) paradedb_agg_source), facet_sql
  end
  it "model with_agg class helper delegates to relation api" do
    sql = MockItem.with_agg(docs: ParadeDB::Aggregations.value_count(:id)).order(:id).limit(10).to_sql

    assert_query_sql %(SELECT mock_items.*, pdb.agg('{"value_count":{"field":"id"}}') OVER () AS _docs_facet FROM mock_items WHERE ("mock_items"."id" @@@ pdb.all()) ORDER BY "mock_items"."id" ASC LIMIT 10), sql
  end
  it "aggregate_by builds grouped aggregation query" do
    sql = MockItem.search(:category)
                     .term("electronics")
                     .aggregate_by(
                       :rating,
                       agg: ParadeDB::Aggregations.value_count(:id)
                     )
                     .order(:rating)
                     .limit(5)
                     .to_sql

    expected = <<~SQL.strip
      SELECT "mock_items"."rating", pdb.agg('{"value_count":{"field":"id"}}') AS agg FROM "mock_items"
      WHERE ("mock_items"."category" === 'electronics')
      GROUP BY "mock_items"."rating"
      ORDER BY "mock_items"."rating" ASC
      LIMIT 5
    SQL

    assert_query_sql expected, sql
  end
  it "model aggregate_by adds match all when no paradedb predicate exists" do
    sql = MockItem.aggregate_by(:rating, agg: ParadeDB::Aggregations.value_count(:id)).to_sql

    assert_query_sql %(SELECT "mock_items"."rating", pdb.agg('{"value_count":{"field":"id"}}') AS agg FROM "mock_items" WHERE ("mock_items"."id" @@@ pdb.all()) GROUP BY "mock_items"."rating"), sql
  end
  it "with facets load requires order and limit" do
    rel = MockItem.search(:description)
                     .match_all("shoes")
                     .with_facets(:category, size: 10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY and LIMIT"
  end
  it "with facets load requires limit" do
    rel = MockItem.search(:description)
                     .match_all("shoes")
                     .with_facets(:category, size: 10)
                     .order(:id)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "LIMIT"
  end
  it "with facets load requires order" do
    rel = MockItem.search(:description)
                     .match_all("shoes")
                     .with_facets(:category, size: 10)
                     .limit(10)

    error = assert_raises(ParadeDB::FacetQueryError) { rel.load }
    assert_includes error.message, "ORDER BY"
  end

  it "nearest adds match-all predicate and distance ordering" do
    sql = MockItem.nearest(:embedding, [1, 2, 3, 4, 5, 6, 7, 8]).limit(2).to_sql

    expected = <<~SQL.strip
      SELECT mock_items.* FROM mock_items
      WHERE ("mock_items"."id" @@@ pdb.all())
      ORDER BY "mock_items"."embedding" <-> '[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0]'::vector ASC
      LIMIT 2
    SQL

    assert_query_sql expected, sql
  end
  it "nearest respects an explicit metric" do
    sql = MockItem.nearest(:embedding, [1, 2, 3, 4, 5, 6, 7, 8], metric: :ip).limit(2).to_sql

    expected = <<~SQL.strip
      SELECT mock_items.* FROM mock_items
      WHERE ("mock_items"."id" @@@ pdb.all())
      ORDER BY "mock_items"."embedding" <#> '[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0]'::vector ASC
      LIMIT 2
    SQL

    assert_query_sql expected, sql
  end
  it "nearest defaults the metric from the index definition" do
    sql = VectorIndexedMockItem.nearest(:embedding, [1, 2, 3, 4, 5, 6, 7, 8]).limit(2).to_sql

    expected = <<~SQL.strip
      SELECT mock_items.* FROM mock_items
      WHERE ("mock_items"."id" @@@ pdb.all())
      ORDER BY "mock_items"."embedding" <=> '[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0]'::vector ASC
      LIMIT 2
    SQL

    assert_query_sql expected, sql
  end
  it "nearest preserves existing paradedb predicates" do
    sql = MockItem.search(:description)
                 .match_all("shoes")
                 .nearest(:embedding, [1, 2, 3, 4, 5, 6, 7, 8], metric: :l2)
                 .limit(2)
                 .to_sql

    expected = <<~SQL.strip
      SELECT mock_items.* FROM mock_items
      WHERE ("mock_items"."description" &&& 'shoes')
      ORDER BY "mock_items"."embedding" <-> '[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0]'::vector ASC
      LIMIT 2
    SQL

    assert_query_sql expected, sql
  end
  it "nearest chains with standard relation filters" do
    sql = MockItem.where(in_stock: true).extending(ParadeDB::SearchMethods)
                 .nearest(:embedding, [1, 2, 3, 4, 5, 6, 7, 8]).limit(5).to_sql

    expected = <<~SQL.strip
      SELECT mock_items.* FROM mock_items
      WHERE "mock_items"."in_stock" = true
        AND ("mock_items"."id" @@@ pdb.all())
      ORDER BY "mock_items"."embedding" <-> '[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0]'::vector ASC
      LIMIT 5
    SQL

    assert_query_sql expected, sql
  end
  it "builds metric-specific vector distance expressions" do
    assert_query_sql %(SELECT "mock_items"."embedding" <-> '[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0]'::vector AS distance FROM "mock_items"), MockItem.select(MockItem.l2_distance(:embedding, [1, 2, 3, 4, 5, 6, 7, 8]).as("distance")).to_sql
    assert_query_sql %(SELECT "mock_items"."embedding" <=> '[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0]'::vector AS distance FROM "mock_items"), MockItem.select(MockItem.cosine_distance(:embedding, [1, 2, 3, 4, 5, 6, 7, 8]).as("distance")).to_sql
    assert_query_sql %(SELECT "mock_items"."embedding" <#> '[1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0]'::vector AS distance FROM "mock_items"), MockItem.select(MockItem.inner_product(:embedding, [1, 2, 3, 4, 5, 6, 7, 8]).as("distance")).to_sql
  end
end
