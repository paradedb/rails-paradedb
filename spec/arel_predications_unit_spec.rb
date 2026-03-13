# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ArelPredicationsUnitTest" do
  before do
    @t = ::Arel::Table.new("products")
  end

  def sql(node)
    ParadeDB::Arel.to_sql(node)
  end

  # ---- pdb_match ----
  it "pdb_match single term" do
    node = @t[:description].pdb_match("shoes")
    assert_equal %("products"."description" &&& 'shoes'), sql(node)
  end
  it "pdb_match multiple terms joined" do
    node = @t[:description].pdb_match("running", "shoes", "lightweight")
    assert_equal %("products"."description" &&& 'running shoes lightweight'), sql(node)
  end
  it "pdb_match with boost" do
    node = @t[:description].pdb_match("shoes", boost: 2.5)
    assert_equal %("products"."description" &&& 'shoes'::pdb.boost(2.5)), sql(node)
  end
  it "pdb_match without boost" do
    node = @t[:description].pdb_match("shoes", boost: nil)
    assert_equal %("products"."description" &&& 'shoes'), sql(node)
  end
  it "pdb_match raises with no terms" do
    assert_raises(ArgumentError) { @t[:description].pdb_match }
  end

  # ---- pdb_match_any ----
  it "pdb_match_any single term" do
    node = @t[:description].pdb_match_any("wireless")
    assert_equal %("products"."description" ||| 'wireless'), sql(node)
  end
  it "pdb_match_any multiple terms" do
    node = @t[:description].pdb_match_any("wireless", "bluetooth", "earbuds")
    assert_equal %("products"."description" ||| 'wireless bluetooth earbuds'), sql(node)
  end
  it "pdb_match with tokenizer override" do
    node = @t[:description].pdb_match("running shoes", tokenizer: "whitespace")
    assert_equal %("products"."description" &&& 'running shoes'::pdb.whitespace), sql(node)
  end
  it "pdb_match with tokenizer args" do
    node = @t[:description].pdb_match("running shoes", tokenizer: "whitespace('lowercase=false')")
    assert_equal %("products"."description" &&& 'running shoes'::pdb.whitespace('lowercase=false')), sql(node)
  end

  # ---- pdb_phrase ----
  it "pdb_phrase without slop" do
    node = @t[:description].pdb_phrase("running shoes")
    assert_equal %("products"."description" ### 'running shoes'), sql(node)
  end
  it "pdb_phrase with slop zero" do
    node = @t[:description].pdb_phrase("running shoes", slop: 0)
    assert_equal %("products"."description" ### 'running shoes'::pdb.slop(0)), sql(node)
  end
  it "pdb_phrase with slop large" do
    node = @t[:description].pdb_phrase("running shoes", slop: 10)
    assert_equal %("products"."description" ### 'running shoes'::pdb.slop(10)), sql(node)
  end
  it "pdb_phrase with tokenizer" do
    node = @t[:description].pdb_phrase("running shoes", tokenizer: "whitespace")
    assert_equal %("products"."description" ### 'running shoes'::pdb.whitespace), sql(node)
  end
  it "pdb_phrase with pretokenized array" do
    node = @t[:description].pdb_phrase(%w[running shoes])
    assert_equal %("products"."description" ### ARRAY['running', 'shoes']), sql(node)
  end

  # ---- pdb_term ----
  it "pdb_term without boost" do
    node = @t[:category].pdb_term("footwear")
    assert_equal %("products"."category" === 'footwear'), sql(node)
  end
  it "pdb_term with float boost" do
    node = @t[:category].pdb_term("footwear", boost: 1.5)
    assert_equal %("products"."category" === 'footwear'::pdb.boost(1.5)), sql(node)
  end
  it "pdb_term with boolean value" do
    node = @t[:in_stock].pdb_term(true)
    assert_equal %("products"."in_stock" === TRUE), sql(node)
  end
  it "pdb_term with integer value" do
    node = @t[:rating].pdb_term(5)
    assert_equal %("products"."rating" === 5), sql(node)
  end
  it "pdb_term_set" do
    node = @t[:category].pdb_term_set(%w[audio footwear])
    assert_equal %("products"."category" @@@ pdb.term_set(ARRAY['audio', 'footwear'])), sql(node)
  end

  # ---- fuzzy options on pdb_term ----
  it "pdb_term with distance" do
    node = @t[:description].pdb_term("shose", distance: 2)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)), sql(node)
  end
  it "pdb_term with prefix true" do
    node = @t[:description].pdb_term("runn", distance: 1, prefix: true)
    assert_equal %("products"."description" === 'runn'::pdb.fuzzy(1, "true")), sql(node)
  end
  it "pdb_term with prefix false" do
    node = @t[:description].pdb_term("shose", distance: 2, prefix: false)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)), sql(node)
  end
  it "pdb_term with transposition cost one" do
    node = @t[:description].pdb_term("shose", distance: 1, transposition_cost_one: true)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(1, "false", "true")), sql(node)
  end
  it "pdb_term with fuzzy boost" do
    node = @t[:description].pdb_term("shose", distance: 2, boost: 1.5)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(1.5)), sql(node)
  end

  # ---- pdb_regex ----
  it "pdb_regex simple" do
    node = @t[:description].pdb_regex("run.*")
    assert_equal %("products"."description" @@@ pdb.regex('run.*')), sql(node)
  end
  it "pdb_regex complex pattern" do
    node = @t[:description].pdb_regex("(wireless|bluetooth).*earbuds")
    assert_equal %("products"."description" @@@ pdb.regex('(wireless|bluetooth).*earbuds')), sql(node)
  end
  it "pdb_regex_phrase" do
    node = @t[:description].pdb_regex_phrase("run.*", "sho.*", slop: 2, max_expansions: 100)
    assert_equal %("products"."description" @@@ pdb.regex_phrase(ARRAY['run.*', 'sho.*'], slop => 2, max_expansions => 100)), sql(node)
  end

  # ---- pdb_near ----
  it "pdb_near distance 1" do
    node = @t[:description].pdb_near("running", anchor: "shoes", distance: 1)
    assert_equal %("products"."description" @@@ ('running' ## 1 ## 'shoes')), sql(node)
  end
  it "pdb_near ordered" do
    node = @t[:description].pdb_near("running", anchor: "shoes", distance: 1, ordered: true)
    assert_equal %("products"."description" @@@ ('running' ##> 1 ##> 'shoes')), sql(node)
  end
  it "pdb_near large distance" do
    node = @t[:description].pdb_near("running", anchor: "shoes", distance: 5)
    assert_equal %("products"."description" @@@ ('running' ## 5 ## 'shoes')), sql(node)
  end
  it "pdb_near with array left operand" do
    node = @t[:description].pdb_near("sleek", "white", anchor: "shoes", distance: 1)
    assert_equal %("products"."description" @@@ (pdb.prox_array('sleek', 'white') ## 1 ## 'shoes')), sql(node)
  end
  it "pdb_near with regex wrapper" do
    node = @t[:description].pdb_near(ParadeDB.regex_term("sl.*"), "white", anchor: "shoes", distance: 1)
    assert_equal %("products"."description" @@@ (pdb.prox_array(pdb.prox_regex('sl.*'), 'white') ## 1 ## 'shoes')), sql(node)
  end

  # ---- pdb_phrase_prefix ----
  it "pdb_phrase_prefix single term" do
    node = @t[:description].pdb_phrase_prefix("run")
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['run'])), sql(node)
  end
  it "pdb_phrase_prefix multiple terms" do
    node = @t[:description].pdb_phrase_prefix("running", "sh")
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['running', 'sh'])), sql(node)
  end
  it "pdb_phrase_prefix with max expansion" do
    node = @t[:description].pdb_phrase_prefix("running", "sh", max_expansion: 100)
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['running', 'sh'], 100)), sql(node)
  end
  it "pdb_phrase_prefix raises with no terms" do
    assert_raises(ArgumentError) { @t[:description].pdb_phrase_prefix }
  end

  # ---- pdb_parse ----
  it "pdb_parse basic" do
    node = @t[:description].pdb_parse("shoes OR boots")
    assert_equal %("products"."description" @@@ pdb.parse('shoes OR boots')), sql(node)
  end
  it "pdb_parse with lenient true" do
    node = @t[:description].pdb_parse("shoes OR", lenient: true)
    assert_equal %("products"."description" @@@ pdb.parse('shoes OR', lenient => true)), sql(node)
  end
  it "pdb_parse with lenient false" do
    node = @t[:description].pdb_parse("shoes", lenient: false)
    assert_equal %("products"."description" @@@ pdb.parse('shoes', lenient => false)), sql(node)
  end
  it "pdb_parse with conjunction_mode true" do
    node = @t[:description].pdb_parse("running shoes", conjunction_mode: true)
    assert_equal %("products"."description" @@@ pdb.parse('running shoes', conjunction_mode => true)), sql(node)
  end

  # ---- pdb_all ----
  it "pdb_all" do
    node = @t[:id].pdb_all
    assert_equal %("products"."id" @@@ pdb.all()), sql(node)
  end
  it "pdb_exists" do
    node = @t[:id].pdb_exists
    assert_equal %("products"."id" @@@ pdb.exists()), sql(node)
  end
  it "pdb_range with Ruby range" do
    node = @t[:rating].pdb_range(3..5)
    assert_equal %("products"."rating" @@@ pdb.range(int8range(3, 5, '[]'))), sql(node)
  end
  it "pdb_range with bound options" do
    node = @t[:rating].pdb_range(gte: 3, lt: 5)
    assert_equal %q{"products"."rating" @@@ pdb.range(int8range(3, 5, '[)'))}, sql(node)
  end
  it "pdb_range_term" do
    node = @t[:weight_range].pdb_range_term("(10, 12]", relation: "Intersects", range_type: "int4range")
    assert_equal %q{"products"."weight_range" @@@ pdb.range_term('(10, 12]'::int4range, 'Intersects')}, sql(node)
  end

  # ---- pdb_more_like_this ----
  it "pdb_more_like_this with integer key" do
    node = @t[:id].pdb_more_like_this(3, fields: [:description])
    assert_equal %("products"."id" @@@ pdb.more_like_this(3, ARRAY['description'])), sql(node)
  end
  it "pdb_more_like_this without fields" do
    node = @t[:id].pdb_more_like_this(3)
    assert_equal %("products"."id" @@@ pdb.more_like_this(3)), sql(node)
  end
  it "pdb_more_like_this with multiple fields" do
    node = @t[:id].pdb_more_like_this(5, fields: [:description, :category])
    assert_equal %("products"."id" @@@ pdb.more_like_this(5, ARRAY['description', 'category'])), sql(node)
  end
  it "pdb_more_like_this with options" do
    node = @t[:id].pdb_more_like_this(
      5,
      fields: [:description],
      options: { min_term_frequency: 2, max_query_terms: 10, stopwords: %w[the a] }
    )
    assert_equal %("products"."id" @@@ pdb.more_like_this(5, ARRAY['description'], min_term_frequency => 2, max_query_terms => 10, stopwords => ARRAY['the', 'a'])), sql(node)
  end

  # ---- pdb_full_text ----
  it "pdb_full_text with string expression" do
    node = @t[:description].pdb_full_text("pdb.all()")
    assert_equal %("products"."description" @@@ pdb.all()), sql(node)
  end

  # ---- pdb_score / pdb_snippet ----
  it "pdb_score renders pdb function" do
    node = @t[:id].pdb_score
    assert_equal %(pdb.score("products"."id")), sql(node)
  end
  it "pdb_snippet no extra args" do
    node = @t[:description].pdb_snippet
    assert_equal %(pdb.snippet("products"."description")), sql(node)
  end
  it "pdb_snippet with tags" do
    node = @t[:description].pdb_snippet("<b>", "</b>")
    assert_equal %(pdb.snippet("products"."description", '<b>', '</b>')), sql(node)
  end
  it "pdb_snippets with named args" do
    node = @t[:description].pdb_snippets(
      start_tag: "<em>",
      end_tag: "</em>",
      max_num_chars: 15,
      limit: 1,
      offset: 0,
      sort_by: "position"
    )
    assert_equal %(pdb.snippets("products"."description", start_tag => '<em>', end_tag => '</em>', max_num_chars => 15, "limit" => 1, "offset" => 0, sort_by => 'position')), sql(node)
  end
  it "pdb_snippet_positions" do
    node = @t[:description].pdb_snippet_positions
    assert_equal %(pdb.snippet_positions("products"."description")), sql(node)
  end

  # ---- Boolean composition with standard AR predicates ----
  it "pdb_match and standard eq compose" do
    node = @t[:description].pdb_match("shoes").and(@t[:in_stock].eq(true))
    rendered = sql(node)
    assert_includes rendered, "&&&"
    assert_includes rendered, "AND"
    assert_includes rendered, "in_stock"
  end
  it "pdb_match or composition" do
    a = @t[:description].pdb_match("shoes")
    b = @t[:description].pdb_match("boots")
    rendered = sql(a.or(b))
    assert_includes rendered, " OR "
    assert_includes rendered, "'shoes'"
    assert_includes rendered, "'boots'"
  end
  it "pdb_match not composition" do
    node = @t[:description].pdb_match("cheap").not
    assert_equal %(NOT ("products"."description" &&& 'cheap')), sql(node)
  end

  # ---- Validation ----
  it "pdb_term raises on non-numeric distance" do
    error = assert_raises(ArgumentError) { @t[:description].pdb_term("shoes", distance: "far") }
    assert_match(/distance must be numeric/, error.message)
  end
  it "pdb_term raises on out-of-range distance" do
    error = assert_raises(ArgumentError) { @t[:description].pdb_term("shoes", distance: 5) }
    assert_match(/between 0 and 2/, error.message)
  end
  it "pdb_match raises on non-numeric boost" do
    error = assert_raises(ArgumentError) { @t[:description].pdb_match("shoes", boost: "high") }
    assert_match(/boost must be numeric/, error.message)
  end
  it "pdb_match raises on invalid tokenizer" do
    error = assert_raises(ArgumentError) { @t[:description].pdb_match("shoes", tokenizer: "bad;tokenizer") }
    assert_match(/invalid tokenizer expression/, error.message)
  end
end
