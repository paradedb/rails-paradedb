# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ArelVisitorTest" do
  before do
    @builder = ParadeDB::Arel::Builder.new(:products)
  end

  def sql(node)
    ParadeDB::Arel.to_sql(node)
  end
  it "match" do
    node = @builder.match(:description, "running", "shoes")
    assert_equal %("products"."description" &&& 'running shoes'), sql(node)
  end
  it "match any" do
    node = @builder.match_any(:description, "wireless", "bluetooth")
    assert_equal %("products"."description" ||| 'wireless bluetooth'), sql(node)
  end
  it "match any with tokenizer override" do
    node = @builder.match_any(:description, "running shoes", tokenizer: "whitespace")
    assert_equal %("products"."description" ||| 'running shoes'::pdb.whitespace), sql(node)
  end
  it "phrase with slop" do
    node = @builder.phrase(:description, "running shoes", slop: 2)
    assert_equal %("products"."description" ### 'running shoes'::pdb.slop(2)), sql(node)
  end
  it "phrase with tokenizer" do
    node = @builder.phrase(:description, "running shoes", tokenizer: "whitespace")
    assert_equal %("products"."description" ### 'running shoes'::pdb.whitespace), sql(node)
  end
  it "phrase with array" do
    node = @builder.phrase(:description, %w[running shoes])
    assert_equal %("products"."description" ### ARRAY['running', 'shoes']), sql(node)
  end
  it "term exact" do
    node = @builder.term(:description, "shoes")
    assert_equal %("products"."description" === 'shoes'), sql(node)
  end
  it "term set" do
    node = @builder.term_set(:category, %w[audio footwear])
    assert_equal %("products"."category" @@@ pdb.term_set(ARRAY['audio', 'footwear'])), sql(node)
  end
  it "term with boost" do
    node = @builder.term(:description, "shoes", boost: 2)
    assert_equal %("products"."description" === 'shoes'::pdb.boost(2)), sql(node)
  end
  it "term with fuzzy prefix" do
    node = @builder.term(:description, "runn", distance: 1, prefix: true)
    assert_equal %("products"."description" === 'runn'::pdb.fuzzy(1, "true")), sql(node)
  end
  it "term with fuzzy boost" do
    node = @builder.term(:description, "shose", distance: 2, boost: 2)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(2)), sql(node)
  end
  it "term with fuzzy prefix and boost" do
    node = @builder.term(:description, "runn", distance: 1, prefix: true, boost: 1.5)
    assert_equal %("products"."description" === 'runn'::pdb.fuzzy(1, "true")::pdb.boost(1.5)), sql(node)
  end
  it "boost" do
    node = @builder.match(:description, "shoes", boost: 2)
    assert_equal %("products"."description" &&& 'shoes'::pdb.boost(2)), sql(node)
  end
  it "regex" do
    node = @builder.regex(:description, "run.*shoes")
    assert_equal %("products"."description" @@@ pdb.regex('run.*shoes')), sql(node)
  end
  it "near" do
    node = @builder.near(:description, ParadeDB.proximity("sleek").within(1, "shoes"))
    assert_equal %("products"."description" @@@ ('sleek' ## 1 ## 'shoes')), sql(node)
  end
  it "near ordered" do
    node = @builder.near(:description, ParadeDB.proximity("sleek").within(1, "shoes", ordered: true))
    assert_equal %("products"."description" @@@ ('sleek' ##> 1 ##> 'shoes')), sql(node)
  end
  it "near with array left operand" do
    node = @builder.near(:description, ParadeDB.proximity("sleek", "white").within(1, "shoes"))
    assert_equal %("products"."description" @@@ (pdb.prox_array('sleek', 'white') ## 1 ## 'shoes')), sql(node)
  end
  it "near with const" do
    node = @builder.near(:description, ParadeDB.proximity("sleek").within(1, "shoes"), const: 1.0)
    assert_equal %("products"."description" @@@ ('sleek' ## 1 ## 'shoes')::pdb.const(1.0)), sql(node)
  end
  it "regex phrase" do
    node = @builder.regex_phrase(:description, "run.*", "sho.*")
    assert_equal %("products"."description" @@@ pdb.regex_phrase(ARRAY['run.*', 'sho.*'])), sql(node)
  end
  it "phrase prefix" do
    node = @builder.phrase_prefix(:description, "running", "sh")
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['running', 'sh'])), sql(node)
  end
  it "phrase prefix with max expansion" do
    node = @builder.phrase_prefix(:description, "running", "sh", max_expansion: 100)
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['running', 'sh'], 100)), sql(node)
  end
  it "parse with conjunction mode" do
    node = @builder.parse(:description, "running shoes", conjunction_mode: true)
    assert_equal %("products"."description" @@@ pdb.parse('running shoes', conjunction_mode => true)), sql(node)
  end
  it "range term relation" do
    node = @builder.range_term(:weight_range, "(10, 12]", relation: "Intersects", range_type: "int4range")
    assert_equal %q{"products"."weight_range" @@@ pdb.range_term('(10, 12]'::int4range, 'Intersects')}, sql(node)
  end
  it "more like this" do
    node = @builder.more_like_this(:id, 3, fields: [:description])
    assert_equal %("products"."id" @@@ pdb.more_like_this(3, ARRAY['description'])), sql(node)
  end
  it "more like this with named options" do
    node = @builder.more_like_this(
      :id,
      3,
      fields: [:description],
      options: { min_term_frequency: 2, stopwords: %w[the a] }
    )
    assert_equal %("products"."id" @@@ pdb.more_like_this(3, ARRAY['description'], min_term_frequency => 2, stopwords => ARRAY['the', 'a'])), sql(node)
  end
  it "full text raw expression" do
    node = @builder.full_text(:description, "pdb.all()")
    assert_equal %("products"."description" @@@ pdb.all()), sql(node)
  end
  it "score" do
    node = @builder.score(:id)
    assert_equal %(pdb.score("products"."id")), sql(node)
  end
  it "snippet" do
    node = @builder.snippet(:description, "<b>", "</b>", 50)
    assert_equal %(pdb.snippet("products"."description", '<b>', '</b>', 50)), sql(node)
  end
  it "snippets" do
    node = @builder.snippets(:description, max_num_chars: 15, limit: 1, offset: 0, sort_by: "position")
    assert_equal %(pdb.snippets("products"."description", max_num_chars => 15, "limit" => 1, "offset" => 0, sort_by => 'position')), sql(node)
  end
  it "snippet positions" do
    node = @builder.snippet_positions(:description)
    assert_equal %(pdb.snippet_positions("products"."description")), sql(node)
  end
  it "agg" do
    node = @builder.agg('{"terms":{"field":"category"}}')
    assert_equal %(pdb.agg('{"terms":{"field":"category"}}')), sql(node)
  end
  it "boolean composition" do
    shoes = @builder.match(:description, "shoes")
    cheap = @builder.match(:description, "cheap")
    predicate = shoes.and(cheap.not)
    expected = %("products"."description" &&& 'shoes' AND NOT ("products"."description" &&& 'cheap'))
    assert_sql_equal expected, sql(predicate)
  end
end
