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

  # ---- fuzzy ----
  it "fuzzy distance only" do
    node = @builder.fuzzy(:description, "shose", distance: 2)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)), sql(node)
  end
  it "fuzzy with prefix true" do
    node = @builder.fuzzy(:description, "runn", distance: 1, prefix: true)
    assert_equal %("products"."description" === 'runn'::pdb.fuzzy(1, "true")), sql(node)
  end
  it "fuzzy with prefix false" do
    node = @builder.fuzzy(:description, "shose", distance: 2, prefix: false)
    # prefix: false should not emit the "true" flag
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)), sql(node)
  end
  it "fuzzy with boost only" do
    node = @builder.fuzzy(:description, "shose", distance: 2, boost: 1.5)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(1.5)), sql(node)
  end
  it "fuzzy with prefix and boost" do
    node = @builder.fuzzy(:description, "runn", distance: 1, prefix: true, boost: 2.0)
    assert_equal %("products"."description" === 'runn'::pdb.fuzzy(1, "true")::pdb.boost(2.0)), sql(node)
  end
  it "fuzzy with distance zero" do
    node = @builder.fuzzy(:description, "shoes", distance: 0)
    assert_equal %("products"."description" === 'shoes'::pdb.fuzzy(0)), sql(node)
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

  # ---- near ----
  it "near default distance" do
    node = @builder.near(:description, "running", "shoes", distance: 1)
    assert_equal %("products"."description" @@@ ('running' ## 1 ## 'shoes')), sql(node)
  end
  it "near large distance" do
    node = @builder.near(:description, "running", "shoes", distance: 5)
    assert_equal %("products"."description" @@@ ('running' ## 5 ## 'shoes')), sql(node)
  end
  it "near requires exactly two terms" do
    assert_raises(ArgumentError) do
      @builder.near(:description, "one", "two", "three", distance: 1)
    end
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
    fuzzy_node = @builder.fuzzy(:description, "shose", distance: 2)
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
