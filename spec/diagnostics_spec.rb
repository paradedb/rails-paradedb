# frozen_string_literal: true

require "spec_helper"

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

RSpec.describe "Vector diagnostic SQL" do
  it "renders vector functions and optional query vectors" do
    connection = double("connection")
    allow(connection).to receive(:quote) { |value| "'#{value}'" }
    %i[vector_info vector_config vector_estimator_info].each do |function|
      expect(connection).to receive(:exec_query).with("SELECT * FROM paradedb.#{function}('search_idx'::regclass, 'embedding'::text)").and_return(double(to_a: []))
      ParadeDB::Diagnostics.public_send(function, "search_idx", "embedding", connection: connection)
    end
    expect(connection).to receive(:exec_query).with("SELECT * FROM paradedb.vector_estimator_info('search_idx'::regclass, 'embedding'::text, ARRAY['[0.1,0.2]']::vector[])").and_return(double(to_a: []))
    ParadeDB::Diagnostics.vector_estimator_info("search_idx", "embedding", queries: [[0.1, 0.2]], connection: connection)
  end
end
