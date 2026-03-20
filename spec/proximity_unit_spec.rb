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

  it "rejects empty base operands" do
    error = assert_raises(ArgumentError) { ParadeDB.proximity([]) }

    assert_includes error.message, "proximity requires at least one term"
  end

  it "rejects empty within operands" do
    error = assert_raises(ArgumentError) { ParadeDB.proximity("running").within(1, []) }

    assert_includes error.message, "within requires at least one term"
  end
end
