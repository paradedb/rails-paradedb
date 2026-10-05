# frozen_string_literal: true

require "spec_helper"
require_relative "support/partitioned_vector_index"

RSpec.describe "Diagnostics" do
  before(:context) do
    setup_test_index
  end

  it "indexes helper returns paradedb index metadata" do
    rows = ParadeDB.paradedb_indexes
    assert_kind_of Array, rows
    assert(rows.any? { |row| row["indexname"] == "mock_items_search_idx" })
  end

  it "index_segments helper returns segment metadata" do
    rows = ParadeDB.paradedb_index_segments("mock_items_search_idx")
    assert_kind_of Array, rows
  end

  it "verify_index helper returns checks" do
    rows = ParadeDB.paradedb_verify_index("mock_items_search_idx", sample_rate: 0.1)
    refute_empty rows
    assert_includes rows.first.keys, "check_name"
    assert_includes rows.first.keys, "passed"
  end

  it "verify_all_indexes helper returns checks" do
    rows = ParadeDB.paradedb_verify_all_indexes(index_pattern: "mock_items_search_idx")
    refute_empty rows
    assert_includes rows.first.keys, "check_name"
    assert_includes rows.first.keys, "passed"
  end
end

RSpec.describe "Partitioned vector index diagnostics" do
  include_context "partitioned vector index"

  it "reports vector configuration before and after reindexing" do
    connection = ActiveRecord::Base.connection
    expect(ParadeDB::Diagnostics.vector_config("pg26_idx", "embedding").first["quantized"]).to eq(false)
    expect(ParadeDB::Diagnostics.vector_info("pg26_idx", "embedding")).not_to be_empty
    connection.execute("ALTER INDEX pg26_idx SET (target_segment_count = 1, max_leaf_size = 16, vector_fields = '{\"embedding\":{\"quantization\":true}}')")
    connection.execute("REINDEX INDEX pg26_idx")
    expect(ParadeDB::Diagnostics.vector_config("pg26_idx", "embedding").first["quantized"]).to eq(true)
    expect(ParadeDB::Diagnostics.vector_estimator_info("pg26_idx", "embedding")).to be_an(Array)
    expect(ParadeDB::Diagnostics.vector_estimator_info("pg26_idx", "embedding", queries: [Array.new(64, 0.1)])).to be_an(Array)
  end
end
