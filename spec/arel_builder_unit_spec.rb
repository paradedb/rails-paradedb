# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ArelBuilderUnitTest" do
  before do
    @builder = ParadeDB::Arel::Builder.new(:products)
    @no_table_builder = ParadeDB::Arel::Builder.new
  end

  def sql(node)
    ParadeDB::Arel.to_sql(node)
  end

  # ---- Builder accessor and basics ----
  it "builder table accessor" do
    assert_equal :products, @builder.table
  end
  it "builder without table" do
    assert_nil @no_table_builder.table
  end
  it "bracket accessor returns attribute" do
    attr = @builder[:description]
    assert_instance_of Arel::Attributes::Attribute, attr
    assert_equal "description", attr.name
    assert_equal "products", attr.relation.name
  end
  it "bracket accessor without table" do
    attr = @no_table_builder[:description]
    assert_instance_of Arel::Nodes::SqlLiteral, attr
    assert_equal "description", sql(attr)
  end
  it "column node with invalid type" do
    error = assert_raises(ArgumentError) do
      @builder.match(123, "term")
    end
    assert_match(/Unsupported column type: Integer/, error.message)
  end
  it "attribute without table renders column only" do
    attr = @no_table_builder[:description]
    assert_equal "description", sql(attr)
  end
  it "attribute with table renders table dot column" do
    attr = @builder[:description]
    assert_equal %("products"."description"), sql(attr)
  end

  # ---- match (matching_all) ----
  it "match single term" do
    node = @builder.match(:description, "shoes")
    assert_equal %("products"."description" &&& 'shoes'), sql(node)
  end
  it "match multiple terms joined" do
    node = @builder.match(:description, "running", "shoes", "lightweight")
    assert_equal %("products"."description" &&& 'running shoes lightweight'), sql(node)
  end
  it "match with boost" do
    node = @builder.match(:description, "shoes", boost: 2.5)
    assert_equal %("products"."description" &&& 'shoes'::pdb.boost(2.5)), sql(node)
  end
  it "match with tokenizer override" do
    node = @builder.match(:description, "running shoes", tokenizer: Tokenizer.whitespace())
    assert_equal %("products"."description" &&& 'running shoes'::pdb.whitespace), sql(node)
  end
  it "match with tokenizer override and args" do
    node = @builder.match(:description, "running shoes", tokenizer: Tokenizer.whitespace(options: {lowercase: false}))
    assert_equal %("products"."description" &&& 'running shoes'::pdb.whitespace('lowercase=false')), sql(node)
  end
  it "match without boost" do
    node = @builder.match(:description, "shoes", boost: nil)
    assert_equal %("products"."description" &&& 'shoes'), sql(node)
  end

  # ---- match_any ----
  it "match any single term" do
    node = @builder.match_any(:description, "wireless")
    assert_equal %("products"."description" ||| 'wireless'), sql(node)
  end
  it "match any multiple terms" do
    node = @builder.match_any(:description, "wireless", "bluetooth", "earbuds")
    assert_equal %("products"."description" ||| 'wireless bluetooth earbuds'), sql(node)
  end

  # ---- phrase ----
  it "phrase without slop" do
    node = @builder.phrase(:description, "running shoes")
    assert_equal %("products"."description" ### 'running shoes'), sql(node)
  end
  it "phrase with slop zero" do
    node = @builder.phrase(:description, "running shoes", slop: 0)
    assert_equal %("products"."description" ### 'running shoes'::pdb.slop(0)), sql(node)
  end
  it "phrase with slop large" do
    node = @builder.phrase(:description, "running shoes", slop: 10)
    assert_equal %("products"."description" ### 'running shoes'::pdb.slop(10)), sql(node)
  end
  it "phrase with tokenizer override" do
    node = @builder.phrase(:description, "running shoes", tokenizer: Tokenizer.whitespace())
    assert_equal %("products"."description" ### 'running shoes'::pdb.whitespace), sql(node)
  end
  it "phrase with slop and constant score bridges through query" do
    node = @builder.phrase(:description, "running shoes", slop: 2, constant_score: 1.0)
    assert_equal %("products"."description" ### 'running shoes'::pdb.slop(2)::pdb.query::pdb.const(1.0)), sql(node)
  end
  it "phrase array renders array literal" do
    node = @builder.phrase(:description, %w[running shoes])
    assert_equal %("products"."description" ### ARRAY['running', 'shoes']), sql(node)
  end
  it "phrase array with slop and constant score bridges through query" do
    node = @builder.phrase(:description, %w[shoes running], slop: 2, constant_score: 1.0)
    assert_equal %("products"."description" ### ARRAY['shoes', 'running']::pdb.slop(2)::pdb.query::pdb.const(1.0)), sql(node)
  end

  # ---- term ----
  it "term without boost" do
    node = @builder.term(:category, "footwear")
    assert_equal %("products"."category" === 'footwear'), sql(node)
  end
  it "term with integer boost" do
    node = @builder.term(:category, "footwear", boost: 3)
    assert_equal %("products"."category" === 'footwear'::pdb.boost(3)), sql(node)
  end
  it "term with float boost" do
    node = @builder.term(:category, "footwear", boost: 1.5)
    assert_equal %("products"."category" === 'footwear'::pdb.boost(1.5)), sql(node)
  end
  it "term with boolean value" do
    node = @builder.term(:in_stock, true)
    assert_equal %("products"."in_stock" === TRUE), sql(node)
  end
  it "term with integer value" do
    node = @builder.term(:rating, 5)
    assert_equal %("products"."rating" === 5), sql(node)
  end
  it "term set with strings" do
    node = @builder.term_set(:category, %w[audio footwear])
    assert_equal %("products"."category" @@@ pdb.term_set(ARRAY['audio', 'footwear'])), sql(node)
  end
  it "term set with integers" do
    node = @builder.term_set(:rating, [4, 5])
    assert_equal %("products"."rating" @@@ pdb.term_set(ARRAY[4, 5])), sql(node)
  end
  it "term set with empty values raises" do
    error = assert_raises(ArgumentError) { @builder.term_set(:category, []) }
    assert_includes error.message, "term_set requires at least one value"
  end

  # ---- fuzzy options (flattened into match/term) ----
  it "term with distance" do
    node = @builder.term(:description, "shose", distance: 2)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)), sql(node)
  end
  it "term with prefix true" do
    node = @builder.term(:description, "runn", distance: 1, prefix: true)
    assert_equal %("products"."description" === 'runn'::pdb.fuzzy(1, "true")), sql(node)
  end
  it "term with prefix false" do
    node = @builder.term(:description, "shose", distance: 2, prefix: false)
    # prefix: false should not emit the "true" flag
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)), sql(node)
  end
  it "term with boost only" do
    node = @builder.term(:description, "shose", distance: 2, boost: 1.5)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(1.5)), sql(node)
  end
  it "term with constant score bridges through query" do
    node = @builder.term(:description, "shose", distance: 2, constant_score: 1.0)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.query::pdb.const(1.0)), sql(node)
  end
  it "term with transposition cost one" do
    node = @builder.term(:description, "shose", distance: 1, transposition_cost_one: true)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(1, "false", "true")), sql(node)
  end
  it "term with prefix and transposition cost one" do
    node = @builder.term(:description, "shose", distance: 1, prefix: true, transposition_cost_one: true)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(1, "true", "true")), sql(node)
  end
  it "matching any with distance" do
    node = @builder.match_any(:description, "shoes", distance: 0)
    assert_equal %("products"."description" ||| 'shoes'::pdb.fuzzy(0)), sql(node)
  end

  # ---- regex ----
  it "regex simple" do
    node = @builder.regex(:description, "run.*")
    assert_equal %("products"."description" @@@ pdb.regex('run.*')), sql(node)
  end
  it "regex complex pattern" do
    node = @builder.regex(:description, "(wireless|bluetooth).*earbuds")
    assert_equal %("products"."description" @@@ pdb.regex('(wireless|bluetooth).*earbuds')), sql(node)
  end
  it "regex phrase" do
    node = @builder.regex_phrase(:description, "run.*", "sho.*")
    assert_equal %("products"."description" @@@ pdb.regex_phrase(ARRAY['run.*', 'sho.*'])), sql(node)
  end
  it "regex phrase with options" do
    node = @builder.regex_phrase(:description, "run.*", "sho.*", slop: 2, max_expansions: 100)
    assert_equal %("products"."description" @@@ pdb.regex_phrase(ARRAY['run.*', 'sho.*'], slop => 2, max_expansions => 100)), sql(node)
  end

  # ---- near ----
  it "near distance 1" do
    node = @builder.near(:description, ParadeDB.proximity("running").within(1, "shoes"))
    assert_equal %("products"."description" @@@ ('running' ## 1 ## 'shoes')), sql(node)
  end
  it "near ordered" do
    node = @builder.near(:description, ParadeDB.proximity("running").within(1, "shoes", ordered: true))
    assert_equal %("products"."description" @@@ ('running' ##> 1 ##> 'shoes')), sql(node)
  end
  it "near large distance" do
    node = @builder.near(:description, ParadeDB.proximity("running").within(5, "shoes"))
    assert_equal %("products"."description" @@@ ('running' ## 5 ## 'shoes')), sql(node)
  end
  it "near with array left operand" do
    node = @builder.near(:description, ParadeDB.proximity("sleek", "white").within(1, "shoes"))
    assert_equal %("products"."description" @@@ (pdb.prox_array('sleek', 'white') ## 1 ## 'shoes')), sql(node)
  end
  it "near with regex wrapper" do
    node = @builder.near(:description, ParadeDB.regex_term("sl.*").within(1, "shoes"))
    assert_equal %("products"."description" @@@ (pdb.prox_regex('sl.*') ## 1 ## 'shoes')), sql(node)
  end
  it "near with mixed array left operand" do
    node = @builder.near(:description, ParadeDB.proximity(ParadeDB.regex_term("sl.*"), "white").within(1, "shoes"))
    assert_equal %("products"."description" @@@ (pdb.prox_array(pdb.prox_regex('sl.*'), 'white') ## 1 ## 'shoes')), sql(node)
  end
  it "near with array right operand" do
    node = @builder.near(:description, ParadeDB.proximity("sleek").within(1, "white", "shoes"))
    assert_equal %("products"."description" @@@ ('sleek' ## 1 ## pdb.prox_array('white', 'shoes'))), sql(node)
  end
  it "near with mixed array right operand" do
    node = @builder.near(:description, ParadeDB.proximity("sleek").within(1, "white", ParadeDB.regex_term("sho.*")))
    assert_equal %("products"."description" @@@ ('sleek' ## 1 ## pdb.prox_array('white', pdb.prox_regex('sho.*')))), sql(node)
  end
  it "near with regex wrapper max expansions" do
    node = @builder.near(:description, ParadeDB.regex_term("sl.*", max_expansions: 100).within(1, "shoes"))
    assert_equal %("products"."description" @@@ (pdb.prox_regex('sl.*', 100) ## 1 ## 'shoes')), sql(node)
  end
  it "near with boost" do
    node = @builder.near(:description, ParadeDB.proximity("running").within(1, "shoes"), boost: 2.0)
    assert_equal %("products"."description" @@@ ('running' ## 1 ## 'shoes')::pdb.boost(2.0)), sql(node)
  end
  it "near with const" do
    node = @builder.near(:description, ParadeDB.proximity("running").within(1, "shoes"), const: 1.0)
    assert_equal %("products"."description" @@@ ('running' ## 1 ## 'shoes')::pdb.const(1.0)), sql(node)
  end
  it "near nested clauses" do
    node = @builder.near(
      :description,
      ParadeDB.proximity(ParadeDB.regex_term("sl.*"), "running")
               .within(1, "shoes")
               .within(3, ParadeDB.regex_term("right").within(3, "associative"))
    )

    assert_equal %("products"."description" @@@ ((pdb.prox_array(pdb.prox_regex('sl.*'), 'running') ## 1 ## 'shoes') ## 3 ## (pdb.prox_regex('right') ## 3 ## 'associative'))), sql(node)
  end
  it "near rejects a non proximity clause" do
    error = assert_raises(ArgumentError) do
      @builder.near(:description, "running")
    end
    assert_includes error.message, "near requires a ParadeDB.proximity"
  end
  it "near rejects a proximity clause without within" do
    error = assert_raises(ArgumentError) do
      @builder.near(:description, ParadeDB.proximity("running"))
    end
    assert_includes error.message, "near requires at least one within clause"
  end
  it "near rejects boost and const together" do
    error = assert_raises(ArgumentError) do
      @builder.near(:description, ParadeDB.proximity("running").within(1, "shoes"), boost: 2.0, const: 1.0)
    end

    assert_includes error.message, "boost and const are mutually exclusive"
  end

  # ---- phrase_prefix ----
  it "phrase prefix single term" do
    node = @builder.phrase_prefix(:description, "run")
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['run'])), sql(node)
  end
  it "phrase prefix multiple terms" do
    node = @builder.phrase_prefix(:description, "running", "sh")
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['running', 'sh'])), sql(node)
  end
  it "phrase prefix with max expansion" do
    node = @builder.phrase_prefix(:description, "running", "sh", max_expansion: 100)
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['running', 'sh'], 100)), sql(node)
  end
  it "phrase prefix three terms" do
    node = @builder.phrase_prefix(:description, "trail", "running", "sh")
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['trail', 'running', 'sh'])), sql(node)
  end
  it "exists wrapper" do
    node = @builder.exists(:id)
    assert_equal %("products"."id" @@@ pdb.exists()), sql(node)
  end
  it "range wrapper with Ruby range" do
    node = @builder.range(:rating, 3..5)
    assert_equal %("products"."rating" @@@ pdb.range(int8range(3, 5, '[]'))), sql(node)
  end
  it "range wrapper with exclusive end range" do
    node = @builder.range(:rating, 3...5)
    assert_equal %q{"products"."rating" @@@ pdb.range(int8range(3, 5, '[)'))}, sql(node)
  end
  it "range wrapper with bound options" do
    node = @builder.range(:rating, nil, gte: 3, lt: 5)
    assert_equal %q{"products"."rating" @@@ pdb.range(int8range(3, 5, '[)'))}, sql(node)
  end
  it "range term scalar value" do
    node = @builder.range_term(:weight_range, 1)
    assert_equal %("products"."weight_range" @@@ pdb.range_term(1)), sql(node)
  end
  it "range term with relation" do
    node = @builder.range_term(:weight_range, "(10, 12]", relation: "Intersects", range_type: "int4range")
    assert_equal %q{"products"."weight_range" @@@ pdb.range_term('(10, 12]'::int4range, 'Intersects')}, sql(node)
  end

  # ---- more_like_this ----
  it "more like this with integer key" do
    node = @builder.more_like_this(:id, 3, fields: [:description])
    assert_equal %("products"."id" @@@ pdb.more_like_this(3, ARRAY['description'])), sql(node)
  end
  it "more like this without fields" do
    node = @builder.more_like_this(:id, 3)
    assert_equal %("products"."id" @@@ pdb.more_like_this(3)), sql(node)
  end
  it "more like this with json string" do
    node = @builder.more_like_this(:id, '{"description": "running shoes"}')
    assert_equal %("products"."id" @@@ pdb.more_like_this('{"description": "running shoes"}')), sql(node)
  end
  it "more like this with multiple fields" do
    node = @builder.more_like_this(:id, 5, fields: [:description, :category])
    assert_equal %("products"."id" @@@ pdb.more_like_this(5, ARRAY['description', 'category'])), sql(node)
  end
  it "more like this with options" do
    node = @builder.more_like_this(
      :id,
      5,
      fields: [:description],
      options: { min_term_frequency: 2, max_query_terms: 10, stopwords: %w[the a] }
    )
    assert_equal %("products"."id" @@@ pdb.more_like_this(5, ARRAY['description'], min_term_frequency => 2, max_query_terms => 10, stopwords => ARRAY['the', 'a'])), sql(node)
  end

  # ---- full_text ----
  it "full text with string expression" do
    node = @builder.full_text(:description, "pdb.all()")
    assert_equal %("products"."description" @@@ pdb.all()), sql(node)
  end
  it "full text with node expression" do
    inner = @builder.match(:description, "shoes")
    node = @builder.full_text(:id, inner)
    rendered = sql(node)
    assert_includes rendered, %("products"."id" @@@)
  end

  # ---- score / snippet / agg ----
  it "score renders pdb function" do
    node = @builder.score(:id)
    assert_equal %(pdb.score("products"."id")), sql(node)
  end
  it "snippet no extra args" do
    node = @builder.snippet(:description)
    assert_equal %(pdb.snippet("products"."description")), sql(node)
  end
  it "snippet with tags" do
    node = @builder.snippet(:description, "<b>", "</b>")
    assert_equal %(pdb.snippet("products"."description", '<b>', '</b>')), sql(node)
  end
  it "snippet with tags and max chars" do
    node = @builder.snippet(:description, "<b>", "</b>", 100)
    assert_equal %(pdb.snippet("products"."description", '<b>', '</b>', 100)), sql(node)
  end
  it "snippets with named args" do
    node = @builder.snippets(
      :description,
      start_tag: "<em>",
      end_tag: "</em>",
      max_num_chars: 15,
      limit: 1,
      offset: 0,
      sort_by: "position"
    )
    assert_equal %(pdb.snippets("products"."description", start_tag => '<em>', end_tag => '</em>', max_num_chars => 15, "limit" => 1, "offset" => 0, sort_by => 'position')), sql(node)
  end
  it "snippet positions" do
    node = @builder.snippet_positions(:description)
    assert_equal %(pdb.snippet_positions("products"."description")), sql(node)
  end
  it "agg json string" do
    node = @builder.agg('{"terms":{"field":"category","size":10}}')
    assert_equal %(pdb.agg('{"terms":{"field":"category","size":10}}')), sql(node)
  end

  # ---- Boolean composition ----
  it "and composition" do
    a = @builder.match(:description, "shoes")
    b = @builder.match(:category, "footwear")
    combined = a.and(b)
    expected = %("products"."description" &&& 'shoes' AND "products"."category" &&& 'footwear')
    assert_sql_equal expected, sql(combined)
  end
  it "or composition" do
    a = @builder.match(:description, "shoes")
    b = @builder.match(:description, "boots")
    combined = a.or(b)
    expected = %(("products"."description" &&& 'shoes' OR "products"."description" &&& 'boots'))
    assert_sql_equal expected, sql(combined)
  end
  it "not composition" do
    a = @builder.match(:description, "cheap")
    negated = a.not
    assert_equal %(NOT ("products"."description" &&& 'cheap')), sql(negated)
  end
  it "nested and or not" do
    shoes = @builder.match(:description, "shoes")
    cheap = @builder.match(:description, "cheap")
    boots = @builder.match(:description, "boots")

    # (shoes AND NOT cheap) OR boots
    combined = shoes.and(cheap.not).or(boots)
    rendered = sql(combined)

    assert_includes rendered, "AND NOT"
    assert_includes rendered, " OR "
    assert_includes rendered, "'shoes'"
    assert_includes rendered, "'cheap'"
    assert_includes rendered, "'boots'"
  end
  it "double negation" do
    a = @builder.match(:description, "shoes")
    double_neg = a.not.not
    assert_equal %(NOT (NOT ("products"."description" &&& 'shoes'))), sql(double_neg)
  end
  it "triple and chain" do
    a = @builder.match(:description, "shoes")
    b = @builder.term(:in_stock, true)
    c = @builder.term(:rating, 5)
    combined = a.and(b).and(c)
    rendered = sql(combined)

    assert_includes rendered, "'shoes'"
    assert_includes rendered, "TRUE"
    assert_includes rendered, "5"
    # Verify nested AND structure
    assert_equal 2, rendered.scan("AND").size
  end

  # ---- to_sql helper and quoting primitives ----
  it "to sql rejects unknown node" do
    unknown = Object.new
    assert_raises(TypeError) { ParadeDB::Arel.to_sql(unknown) }
  end
  it "build quoted string" do
    assert_equal "'hello'", sql(Arel::Nodes.build_quoted("hello"))
  end
  it "build quoted integer" do
    assert_equal "42", sql(Arel::Nodes.build_quoted(42))
  end
  it "build quoted boolean" do
    assert_equal "TRUE", sql(Arel::Nodes.build_quoted(true))
  end

  # ---- ParadeDB::Arel.sql helper ----
  it "arel sql helper" do
    literal = ParadeDB::Arel.sql("pdb.all()")
    assert_instance_of Arel::Nodes::SqlLiteral, literal
    assert_equal "pdb.all()", sql(literal)
  end

  # ---- Edge cases: special characters ----
  it "match with single quote in term" do
    node = @builder.match(:description, "shoe's")
    rendered = sql(node)
    # Should be properly quoted (escaped single quote)
    assert_includes rendered, "&&&"
    refute_includes rendered, "shoe's'" # no unescaped quote
  end
  it "regex with backslash" do
    node = @builder.regex(:description, "foo\\\\bar")
    rendered = sql(node)
    assert_includes rendered, "pdb.regex("
  end

  # ---- Cross-operator composition ----
  it "match and regex composed" do
    match_node = @builder.match(:description, "shoes")
    regex_node = @builder.regex(:description, "run.*")
    combined = match_node.and(regex_node)
    rendered = sql(combined)

    assert_includes rendered, "&&&"
    assert_includes rendered, "@@@"
    assert_includes rendered, "pdb.regex"
    assert_includes rendered, "AND"
  end
  it "term or fuzzy composed" do
    term_node = @builder.term(:description, "shoes")
    fuzzy_node = @builder.term(:description, "shose", distance: 2)
    combined = term_node.or(fuzzy_node)
    rendered = sql(combined)

    assert_includes rendered, "==="
    assert_includes rendered, "pdb.fuzzy"
    assert_includes rendered, " OR "
  end
  it "phrase and not match composed" do
    phrase_node = @builder.phrase(:description, "running shoes", slop: 2)
    match_node = @builder.match(:description, "cheap")
    combined = phrase_node.and(match_node.not)
    rendered = sql(combined)

    assert_includes rendered, "###"
    assert_includes rendered, "pdb.slop(2)"
    assert_includes rendered, "AND NOT"
    assert_includes rendered, "'cheap'"
  end
end
