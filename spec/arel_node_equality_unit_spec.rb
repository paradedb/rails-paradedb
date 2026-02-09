# frozen_string_literal: true

require "spec_helper"

class ArelNodeEqualityUnitTest < Minitest::Test
  Nodes = ParadeDB::Arel::Nodes

  def test_boost_cast_equality
    node1 = Nodes::BoostCast.new("expr", 2.0)
    node2 = Nodes::BoostCast.new("expr", 2.0)
    node3 = Nodes::BoostCast.new("expr", 3.0)
    node4 = Nodes::BoostCast.new("other", 2.0)

    assert_equal node1, node2
    assert_equal node1.hash, node2.hash
    refute_equal node1, node3
    refute_equal node1, node4
  end

  def test_slop_cast_equality
    node1 = Nodes::SlopCast.new("expr", 5)
    node2 = Nodes::SlopCast.new("expr", 5)
    node3 = Nodes::SlopCast.new("expr", 10)

    assert_equal node1, node2
    assert_equal node1.hash, node2.hash
    refute_equal node1, node3
  end

  def test_fuzzy_cast_equality
    node1 = Nodes::FuzzyCast.new("expr", 2, prefix: true)
    node2 = Nodes::FuzzyCast.new("expr", 2, prefix: true)
    node3 = Nodes::FuzzyCast.new("expr", 2, prefix: false)
    node4 = Nodes::FuzzyCast.new("expr", 1, prefix: true)

    assert_equal node1, node2
    assert_equal node1.hash, node2.hash
    refute_equal node1, node3
    refute_equal node1, node4
  end

  def test_array_literal_equality
    node1 = Nodes::ArrayLiteral.new(["a", "b"])
    node2 = Nodes::ArrayLiteral.new(["a", "b"])
    node3 = Nodes::ArrayLiteral.new(["a", "c"])

    assert_equal node1, node2
    assert_equal node1.hash, node2.hash
    refute_equal node1, node3
  end

  def test_parse_node_equality
    node1 = Nodes::ParseNode.new("query", lenient: true)
    node2 = Nodes::ParseNode.new("query", lenient: true)
    node3 = Nodes::ParseNode.new("query", lenient: false)
    node4 = Nodes::ParseNode.new("other", lenient: true)

    assert_equal node1, node2
    assert_equal node1.hash, node2.hash
    refute_equal node1, node3
    refute_equal node1, node4
  end

  def test_different_node_types_are_not_equal
    boost = Nodes::BoostCast.new("val", 1.0)
    slop = Nodes::SlopCast.new("val", 1.0)

    refute_equal boost, slop
  end
end
