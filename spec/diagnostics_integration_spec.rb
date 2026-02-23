# frozen_string_literal: true

require "set"
require "spec_helper"

RSpec.describe "DiagnosticsIntegrationTest" do
  before do
    skip "Diagnostics integration tests require PostgreSQL" unless postgresql?

    ensure_paradedb_setup!
    require_diagnostic_functions!
  end

  it "indexes helper returns bm25 index metadata" do
    rows = ParadeDB.paradedb_indexes
    assert_kind_of Array, rows
    assert rows.any? { |row| row["indexname"] == "products_bm25_idx" }
  end

  it "index_segments helper returns segment metadata" do
    rows = ParadeDB.paradedb_index_segments("products_bm25_idx")
    refute_empty rows
    assert_includes rows.first.keys, "segment_idx"
    assert_includes rows.first.keys, "segment_id"
  end

  it "verify_index helper returns checks" do
    rows = ParadeDB.paradedb_verify_index("products_bm25_idx", sample_rate: 0.1)
    refute_empty rows
    assert_includes rows.first.keys, "check_name"
    assert_includes rows.first.keys, "passed"
  end

  it "verify_all_indexes helper returns checks" do
    rows = ParadeDB.paradedb_verify_all_indexes(index_pattern: "products_bm25_idx")
    refute_empty rows
    assert_includes rows.first.keys, "check_name"
    assert_includes rows.first.keys, "passed"
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end

  def ensure_paradedb_setup!
    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.execute("DROP INDEX IF EXISTS products_bm25_idx;")
    conn.execute(<<~SQL)
      CREATE INDEX products_bm25_idx ON products
      USING bm25 (id, description, category, rating, in_stock, price)
      WITH (key_field='id');
    SQL
  end

  def require_diagnostic_functions!
    conn = ActiveRecord::Base.connection
    rows = conn.exec_query(<<~SQL)
      SELECT DISTINCT p.proname
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdb'
        AND p.proname IN ('indexes', 'index_segments', 'verify_index', 'verify_all_indexes')
    SQL

    available = rows.to_a.map { |row| row["proname"] }.to_set
    required = Set.new(%w[indexes index_segments verify_index verify_all_indexes])
    missing = required - available
    skip "ParadeDB diagnostics not available in this pg_search version: #{missing.to_a.sort.join(', ')}" unless missing.empty?
  end
end
