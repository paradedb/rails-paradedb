# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Diagnostics" do
  before(:context) do
    setup_test_index
  end

  it "indexes helper returns paradedb index metadata" do
    rows = ParadeDB.paradedb_indexes
    assert_kind_of Array, rows
    assert(rows.any? { |row| row["indexname"] == "products_search_idx" })
  end

  it "index_segments helper returns segment metadata" do
    rows = ParadeDB.paradedb_index_segments("products_search_idx")
    assert_kind_of Array, rows
  end

  it "verify_index helper returns checks" do
    rows = ParadeDB.paradedb_verify_index("products_search_idx", sample_rate: 0.1)
    refute_empty rows
    assert_includes rows.first.keys, "check_name"
    assert_includes rows.first.keys, "passed"
  end

  it "verify_all_indexes helper returns checks" do
    rows = ParadeDB.paradedb_verify_all_indexes(index_pattern: "products_search_idx")
    refute_empty rows
    assert_includes rows.first.keys, "check_name"
    assert_includes rows.first.keys, "passed"
  end
end
