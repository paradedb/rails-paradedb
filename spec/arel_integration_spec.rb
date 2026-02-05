# frozen_string_literal: true

require "spec_helper"

class ArelIntegrationTest < Minitest::Test
  def setup
    @builder = ParadeDB::Arel::Builder.new(:products)
  end

  def sql(node)
    ParadeDB::Arel.to_sql(node)
  end

  def test_full_matrix_of_operators
    nodes = []
    nodes << @builder.match(:description, "running", "shoes")
    nodes << @builder.match_any(:description, "wireless", "bluetooth")
    nodes << @builder.phrase(:description, "running shoes", slop: 2)
    nodes << @builder.fuzzy(:description, "shose", distance: 2, prefix: false, boost: 2)
    nodes << @builder.term(:description, "literal")
    nodes << @builder.regex(:description, "run.*")
    nodes << @builder.near(:description, "sleek", "shoes", distance: 1)
    nodes << @builder.phrase_prefix(:description, "run", "sh")
    nodes << @builder.more_like_this(:id, 5, fields: [:description, :category])
    nodes << @builder.full_text(:description, "pdb.all()")

    rendered = nodes.map { |n| sql(n) }

    assert_includes rendered, %("products"."description" &&& 'running shoes')
    assert_includes rendered, %("products"."description" ||| 'wireless bluetooth')
    assert_includes rendered, %("products"."description" ### 'running shoes'::pdb.slop(2))
    assert_includes rendered, %("products"."description" === 'shose'::pdb.fuzzy(2)::pdb.boost(2))
    assert_includes rendered, %("products"."description" === 'literal')
    assert_includes rendered, %("products"."description" @@@ pdb.regex('run.*'))
    assert_includes rendered, %("products"."description" @@@ ('sleek' ## 1 ## 'shoes'))
    assert_includes rendered, %("products"."description" @@@ pdb.phrase_prefix(ARRAY['run', 'sh']))
    assert_includes rendered, %("products"."id" @@@ pdb.more_like_this(5, ARRAY['description', 'category']))
    assert_includes rendered, %("products"."description" @@@ 'pdb.all()')
  end

  def test_boolean_chains
    base = @builder.match(:description, "running").and(
      @builder.phrase(:description, "trail shoes").not
    )

    other = @builder.match_any(:category, "Footwear").and(
      @builder.term(:in_stock, true)
    )

    combined = base.or(other)

    assert_equal %((("products"."description" &&& 'running' AND NOT ("products"."description" ### 'trail shoes')) OR ("products"."category" ||| 'Footwear' AND "products"."in_stock" === TRUE))), sql(combined)
  end
end
