# frozen_string_literal: true

require "spec_helper"

class ArelBuilderUnitTest < Minitest::Test
  def setup
    @builder = ParadeDB::Arel::Builder.new(:products)
    @no_table_builder = ParadeDB::Arel::Builder.new
  end

  def sql(node)
    ParadeDB::Arel.to_sql(node)
  end

  # ---- Builder accessor and basics ----

  def test_builder_table_accessor
    assert_equal :products, @builder.table
  end

  def test_builder_without_table
    assert_nil @no_table_builder.table
  end

  def test_bracket_accessor_returns_attribute
    attr = @builder[:description]
    assert_instance_of Arel::Attributes::Attribute, attr
    assert_equal "description", attr.name
    assert_equal "products", attr.relation.name
  end

  def test_bracket_accessor_without_table
    attr = @no_table_builder[:description]
    assert_instance_of Arel::Nodes::SqlLiteral, attr
    assert_equal %("description"), sql(attr)
  end

  def test_column_node_with_invalid_type
    error = assert_raises(ArgumentError) do
      @builder.match(123, "term")
    end
    assert_match(/Unsupported column type: Integer/, error.message)
  end

  def test_attribute_without_table_renders_column_only
    attr = @no_table_builder[:description]
    assert_equal %("description"), sql(attr)
  end

  def test_attribute_with_table_renders_table_dot_column
    attr = @builder[:description]
    assert_equal %("products"."description"), sql(attr)
  end

  # ---- match (matching_all) ----

  def test_match_single_term
    node = @builder.match(:description, "shoes")
    assert_equal %("products"."description" &&& 'shoes'), sql(node)
  end

  def test_match_multiple_terms_joined
    node = @builder.match(:description, "running", "shoes", "lightweight")
    assert_equal %("products"."description" &&& 'running shoes lightweight'), sql(node)
  end

  def test_match_with_boost
    node = @builder.match(:description, "shoes", boost: 2.5)
    assert_equal %("products"."description" &&& 'shoes'::pdb.boost(2.5)), sql(node)
  end

  def test_match_without_boost
    node = @builder.match(:description, "shoes", boost: nil)
    assert_equal %("products"."description" &&& 'shoes'), sql(node)
  end

  # ---- match_any ----

  def test_match_any_single_term
    node = @builder.match_any(:description, "wireless")
    assert_equal %("products"."description" ||| 'wireless'), sql(node)
  end

  def test_match_any_multiple_terms
    node = @builder.match_any(:description, "wireless", "bluetooth", "earbuds")
    assert_equal %("products"."description" ||| 'wireless bluetooth earbuds'), sql(node)
  end

  # ---- phrase ----

  def test_phrase_without_slop
    node = @builder.phrase(:description, "running shoes")
    assert_equal %("products"."description" ### 'running shoes'), sql(node)
  end

  def test_phrase_with_slop_zero
    node = @builder.phrase(:description, "running shoes", slop: 0)
    assert_equal %("products"."description" ### 'running shoes'::pdb.slop(0)), sql(node)
  end

  def test_phrase_with_slop_large
    node = @builder.phrase(:description, "running shoes", slop: 10)
    assert_equal %("products"."description" ### 'running shoes'::pdb.slop(10)), sql(node)
  end

  # ---- term ----

  def test_term_without_boost
    node = @builder.term(:category, "footwear")
    assert_equal %("products"."category" === 'footwear'), sql(node)
  end

  def test_term_with_integer_boost
    node = @builder.term(:category, "footwear", boost: 3)
    assert_equal %("products"."category" === 'footwear'::pdb.boost(3)), sql(node)
  end

  def test_term_with_float_boost
    node = @builder.term(:category, "footwear", boost: 1.5)
    assert_equal %("products"."category" === 'footwear'::pdb.boost(1.5)), sql(node)
  end

  def test_term_with_boolean_value
    node = @builder.term(:in_stock, true)
    assert_equal %("products"."in_stock" === TRUE), sql(node)
  end

  def test_term_with_integer_value
    node = @builder.term(:rating, 5)
    assert_equal %("products"."rating" === 5), sql(node)
  end

  # ---- fuzzy ----

  def test_fuzzy_distance_only
    node = @builder.fuzzy(:description, "shose", distance: 2)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)), sql(node)
  end

  def test_fuzzy_with_prefix_true
    node = @builder.fuzzy(:description, "runn", distance: 1, prefix: true)
    assert_equal %("products"."description" === 'runn'::pdb.fuzzy(1, "true")), sql(node)
  end

  def test_fuzzy_with_prefix_false
    node = @builder.fuzzy(:description, "shose", distance: 2, prefix: false)
    # prefix: false should not emit the "true" flag
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)), sql(node)
  end

  def test_fuzzy_with_boost_only
    node = @builder.fuzzy(:description, "shose", distance: 2, boost: 1.5)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(1.5)), sql(node)
  end

  def test_fuzzy_with_prefix_and_boost
    node = @builder.fuzzy(:description, "runn", distance: 1, prefix: true, boost: 2.0)
    assert_equal %("products"."description" === 'runn'::pdb.fuzzy(1, "true")::pdb.boost(2.0)), sql(node)
  end

  def test_fuzzy_with_distance_zero
    node = @builder.fuzzy(:description, "shoes", distance: 0)
    assert_equal %("products"."description" === 'shoes'::pdb.fuzzy(0)), sql(node)
  end

  # ---- regex ----

  def test_regex_simple
    node = @builder.regex(:description, "run.*")
    assert_equal %("products"."description" @@@ pdb.regex('run.*')), sql(node)
  end

  def test_regex_complex_pattern
    node = @builder.regex(:description, "(wireless|bluetooth).*earbuds")
    assert_equal %("products"."description" @@@ pdb.regex('(wireless|bluetooth).*earbuds')), sql(node)
  end

  # ---- near ----

  def test_near_default_distance
    node = @builder.near(:description, "running", "shoes", distance: 1)
    assert_equal %("products"."description" @@@ ('running' ## 1 ## 'shoes')), sql(node)
  end

  def test_near_large_distance
    node = @builder.near(:description, "running", "shoes", distance: 5)
    assert_equal %("products"."description" @@@ ('running' ## 5 ## 'shoes')), sql(node)
  end

  def test_near_requires_exactly_two_terms
    assert_raises(ArgumentError) do
      @builder.near(:description, "one", "two", "three", distance: 1)
    end
  end

  # ---- phrase_prefix ----

  def test_phrase_prefix_single_term
    node = @builder.phrase_prefix(:description, "run")
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['run'])), sql(node)
  end

  def test_phrase_prefix_multiple_terms
    node = @builder.phrase_prefix(:description, "running", "sh")
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['running', 'sh'])), sql(node)
  end

  def test_phrase_prefix_three_terms
    node = @builder.phrase_prefix(:description, "trail", "running", "sh")
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['trail', 'running', 'sh'])), sql(node)
  end

  # ---- more_like_this ----

  def test_more_like_this_with_integer_key
    node = @builder.more_like_this(:id, 3, fields: [:description])
    assert_equal %("products"."id" @@@ pdb.more_like_this(3, ARRAY['description'])), sql(node)
  end

  def test_more_like_this_without_fields
    node = @builder.more_like_this(:id, 3)
    assert_equal %("products"."id" @@@ pdb.more_like_this(3)), sql(node)
  end

  def test_more_like_this_with_json_string
    node = @builder.more_like_this(:id, '{"description": "running shoes"}')
    assert_equal %("products"."id" @@@ pdb.more_like_this('{"description": "running shoes"}')), sql(node)
  end

  def test_more_like_this_with_multiple_fields
    node = @builder.more_like_this(:id, 5, fields: [:description, :category])
    assert_equal %("products"."id" @@@ pdb.more_like_this(5, ARRAY['description', 'category'])), sql(node)
  end

  def test_more_like_this_with_options
    node = @builder.more_like_this(
      :id,
      5,
      fields: [:description],
      options: { min_term_frequency: 2, max_query_terms: 10, stopwords: %w[the a] }
    )
    assert_equal %("products"."id" @@@ pdb.more_like_this(5, ARRAY['description'], min_term_frequency => 2, max_query_terms => 10, stopwords => ARRAY['the', 'a'])), sql(node)
  end

  # ---- full_text ----

  def test_full_text_with_string_expression
    node = @builder.full_text(:description, "pdb.all()")
    assert_equal %("products"."description" @@@ pdb.all()), sql(node)
  end

  def test_full_text_with_node_expression
    inner = @builder.match(:description, "shoes")
    node = @builder.full_text(:id, inner)
    rendered = sql(node)
    assert_includes rendered, %("products"."id" @@@)
  end

  # ---- score / snippet / agg ----

  def test_score_renders_pdb_function
    node = @builder.score(:id)
    assert_equal %(pdb.score("products"."id")), sql(node)
  end

  def test_snippet_no_extra_args
    node = @builder.snippet(:description)
    assert_equal %(pdb.snippet("products"."description")), sql(node)
  end

  def test_snippet_with_tags
    node = @builder.snippet(:description, "<b>", "</b>")
    assert_equal %(pdb.snippet("products"."description", '<b>', '</b>')), sql(node)
  end

  def test_snippet_with_tags_and_max_chars
    node = @builder.snippet(:description, "<b>", "</b>", 100)
    assert_equal %(pdb.snippet("products"."description", '<b>', '</b>', 100)), sql(node)
  end

  def test_agg_json_string
    node = @builder.agg('{"terms":{"field":"category","size":10}}')
    assert_equal %(pdb.agg('{"terms":{"field":"category","size":10}}')), sql(node)
  end

  # ---- Boolean composition ----

  def test_and_composition
    a = @builder.match(:description, "shoes")
    b = @builder.match(:category, "footwear")
    combined = a.and(b)
    expected = %("products"."description" &&& 'shoes' AND "products"."category" &&& 'footwear')
    assert_sql_equal expected, sql(combined)
  end

  def test_or_composition
    a = @builder.match(:description, "shoes")
    b = @builder.match(:description, "boots")
    combined = a.or(b)
    expected = %(("products"."description" &&& 'shoes' OR "products"."description" &&& 'boots'))
    assert_sql_equal expected, sql(combined)
  end

  def test_not_composition
    a = @builder.match(:description, "cheap")
    negated = a.not
    assert_equal %(NOT ("products"."description" &&& 'cheap')), sql(negated)
  end

  def test_nested_and_or_not
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

  def test_double_negation
    a = @builder.match(:description, "shoes")
    double_neg = a.not.not
    assert_equal %(NOT (NOT ("products"."description" &&& 'shoes'))), sql(double_neg)
  end

  def test_triple_and_chain
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

  def test_to_sql_rejects_unknown_node
    unknown = Object.new
    assert_raises(TypeError) { ParadeDB::Arel.to_sql(unknown) }
  end

  def test_build_quoted_string
    assert_equal "'hello'", sql(Arel::Nodes.build_quoted("hello"))
  end

  def test_build_quoted_integer
    assert_equal "42", sql(Arel::Nodes.build_quoted(42))
  end

  def test_build_quoted_boolean
    assert_equal "TRUE", sql(Arel::Nodes.build_quoted(true))
  end

  # ---- ParadeDB::Arel.sql helper ----

  def test_arel_sql_helper
    literal = ParadeDB::Arel.sql("pdb.all()")
    assert_instance_of Arel::Nodes::SqlLiteral, literal
    assert_equal "pdb.all()", sql(literal)
  end

  # ---- Edge cases: special characters ----

  def test_match_with_single_quote_in_term
    node = @builder.match(:description, "shoe's")
    rendered = sql(node)
    # Should be properly quoted (escaped single quote)
    assert_includes rendered, "&&&"
    refute_includes rendered, "shoe's'" # no unescaped quote
  end

  def test_regex_with_backslash
    node = @builder.regex(:description, "foo\\\\bar")
    rendered = sql(node)
    assert_includes rendered, "pdb.regex("
  end

  # ---- Cross-operator composition ----

  def test_match_and_regex_composed
    match_node = @builder.match(:description, "shoes")
    regex_node = @builder.regex(:description, "run.*")
    combined = match_node.and(regex_node)
    rendered = sql(combined)

    assert_includes rendered, "&&&"
    assert_includes rendered, "@@@"
    assert_includes rendered, "pdb.regex"
    assert_includes rendered, "AND"
  end

  def test_term_or_fuzzy_composed
    term_node = @builder.term(:description, "shoes")
    fuzzy_node = @builder.fuzzy(:description, "shose", distance: 2)
    combined = term_node.or(fuzzy_node)
    rendered = sql(combined)

    assert_includes rendered, "==="
    assert_includes rendered, "pdb.fuzzy"
    assert_includes rendered, " OR "
  end

  def test_phrase_and_not_match_composed
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
