# frozen_string_literal: true

require "spec_helper"

class ArelVisitorTest < Minitest::Test
  def setup
    @builder = ParadeDB::Arel::Builder.new(:products)
  end

  def sql(node)
    ParadeDB::Arel.to_sql(node)
  end

  def test_match
    node = @builder.match(:description, "running", "shoes")
    assert_equal %("products"."description" &&& 'running shoes'), sql(node)
  end

  def test_match_any
    node = @builder.match_any(:description, "wireless", "bluetooth")
    assert_equal %("products"."description" ||| 'wireless bluetooth'), sql(node)
  end

  def test_phrase_with_slop
    node = @builder.phrase(:description, "running shoes", slop: 2)
    assert_equal %("products"."description" ### 'running shoes'::pdb.slop(2)), sql(node)
  end

  def test_term_exact
    node = @builder.term(:description, "shoes")
    assert_equal %("products"."description" === 'shoes'), sql(node)
  end

  def test_term_with_boost
    node = @builder.term(:description, "shoes", boost: 2)
    assert_equal %("products"."description" === 'shoes'::pdb.boost(2)), sql(node)
  end

  def test_fuzzy_with_prefix
    node = @builder.fuzzy(:description, "runn", distance: 1, prefix: true)
    assert_equal %("products"."description" === 'runn'::pdb.fuzzy(1, "true")), sql(node)
  end

  def test_fuzzy_with_boost
    node = @builder.fuzzy(:description, "shose", distance: 2, boost: 2)
    assert_equal %("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(2)), sql(node)
  end

  def test_fuzzy_with_prefix_and_boost
    node = @builder.fuzzy(:description, "runn", distance: 1, prefix: true, boost: 1.5)
    assert_equal %("products"."description" === 'runn'::pdb.fuzzy(1, "true")::pdb.boost(1.5)), sql(node)
  end

  def test_boost
    node = @builder.match(:description, "shoes", boost: 2)
    assert_equal %("products"."description" &&& 'shoes'::pdb.boost(2)), sql(node)
  end

  def test_regex
    node = @builder.regex(:description, "run.*shoes")
    assert_equal %("products"."description" @@@ pdb.regex('run.*shoes')), sql(node)
  end

  def test_near
    node = @builder.near(:description, "sleek", "shoes", distance: 1)
    assert_equal %("products"."description" @@@ ('sleek' ## 1 ## 'shoes')), sql(node)
  end

  def test_phrase_prefix
    node = @builder.phrase_prefix(:description, "running", "sh")
    assert_equal %("products"."description" @@@ pdb.phrase_prefix(ARRAY['running', 'sh'])), sql(node)
  end

  def test_more_like_this
    node = @builder.more_like_this(:id, 3, fields: [:description])
    assert_equal %("products"."id" @@@ pdb.more_like_this(3, ARRAY['description'])), sql(node)
  end

  def test_more_like_this_with_named_options
    node = @builder.more_like_this(
      :id,
      3,
      fields: [:description],
      options: { min_term_frequency: 2, stopwords: %w[the a] }
    )
    assert_equal %("products"."id" @@@ pdb.more_like_this(3, ARRAY['description'], min_term_frequency => 2, stopwords => ARRAY['the', 'a'])), sql(node)
  end

  def test_full_text_raw_expression
    node = @builder.full_text(:description, "pdb.all()")
    assert_equal %("products"."description" @@@ pdb.all()), sql(node)
  end

  def test_score
    node = @builder.score(:id)
    assert_equal %(pdb.score("products"."id")), sql(node)
  end

  def test_snippet
    node = @builder.snippet(:description, "<b>", "</b>", 50)
    assert_equal %(pdb.snippet("products"."description", '<b>', '</b>', 50)), sql(node)
  end

  def test_agg
    node = @builder.agg('{"terms":{"field":"category"}}')
    assert_equal %(pdb.agg('{"terms":{"field":"category"}}')), sql(node)
  end

  def test_boolean_composition
    shoes = @builder.match(:description, "shoes")
    cheap = @builder.match(:description, "cheap")
    predicate = shoes.and(cheap.not)
    expected = %("products"."description" &&& 'shoes' AND NOT ("products"."description" &&& 'cheap'))
    assert_sql_equal expected, sql(predicate)
  end
end
