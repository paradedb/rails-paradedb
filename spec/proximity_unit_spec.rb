# frozen_string_literal: true

require "spec_helper"

RSpec.describe ParadeDB::Proximity::RegexTerm do
  it "builds a regex wrapper" do
    regex_term = ParadeDB.regex_term("sl.*", max_expansions: 100)

    assert_equal "sl.*", regex_term.pattern
    assert_equal 100, regex_term.max_expansions
  end

  it "rejects non-string patterns" do
    error = assert_raises(ArgumentError) { ParadeDB.regex_term(123) }

    assert_includes error.message, "pattern must be a String"
  end

  it "rejects non-integer max expansions" do
    error = assert_raises(ArgumentError) { ParadeDB.regex_term("sl.*", max_expansions: "100") }

    assert_includes error.message, "max_expansions must be an integer"
  end

  it "chains into a proximity clause" do
    clause = ParadeDB.regex_term("sl.*").within(1, "shoes")

    assert_instance_of ParadeDB::Proximity::Clause, clause
    assert_instance_of ParadeDB::Proximity::RegexTerm, clause.operand
    assert_equal 1, clause.clauses.first.distance
    assert_equal "shoes", clause.clauses.first.operand
  end
end

RSpec.describe ParadeDB::Proximity::Clause do
  it "builds from a single term" do
    clause = ParadeDB.proximity("running")

    assert_equal "running", clause.operand
    assert_empty clause.clauses
  end

  it "builds from multiple terms" do
    clause = ParadeDB.proximity("sleek", "white")

    assert_equal ["sleek", "white"], clause.operand
  end

  it "returns a new clause when chaining" do
    base = ParadeDB.proximity("running")
    chained = base.within(1, "shoes")

    assert_empty base.clauses
    assert_equal 1, chained.clauses.length
  end

  it "supports nested clauses" do
    nested = ParadeDB.proximity("right").within(3, "associative")
    clause = ParadeDB.proximity(ParadeDB.regex_term("sl.*"), "running").within(3, nested)

    assert_equal nested, clause.clauses.first.operand
  end

  it "rejects empty base operands" do
    error = assert_raises(ArgumentError) { ParadeDB.proximity([]) }

    assert_includes error.message, "proximity requires at least one term"
  end

  it "rejects empty within operands" do
    error = assert_raises(ArgumentError) { ParadeDB.proximity("running").within(1, []) }

    assert_includes error.message, "within requires at least one term"
  end
end
