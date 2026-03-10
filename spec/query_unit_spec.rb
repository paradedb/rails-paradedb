# frozen_string_literal: true

require "spec_helper"

RSpec.describe "QueryUnitTest" do
  it "builds regex query json" do
    query = ParadeDB::Query.regex("key.*")

    assert_equal({ "regex" => { "pattern" => "key.*" } }, query)
  end

  it "rejects non-string regex pattern" do
    error = assert_raises(ArgumentError) { ParadeDB::Query.regex(123) }

    assert_includes error.message, "pattern must be a String"
  end
end
