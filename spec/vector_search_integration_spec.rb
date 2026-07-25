# frozen_string_literal: true

require "spec_helper"

class VectorItem < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :vector_items
end

class VectorItemIndex < ParadeDB::Index
  self.table_name = :vector_items
  self.key_field = :id
  self.fields = {
    id: {},
    label: {},
    embedding: { metric: :l2 }
  }
end

RSpec.describe "VectorSearchIntegrationTest" do
  before do
    skip "Vector search integration test requires PostgreSQL" unless postgresql?
    skip "Vector search integration test requires the pgvector extension" unless pgvector_available?

    ensure_vector_schema!
    seed_vector_items!
  end

  it "round-trips vector values through a vector(n) column" do
    column = VectorItem.columns_hash["embedding"]
    assert_equal :vector, column.type
    assert_equal "vector(3)", column.sql_type
    assert_equal 3, column.limit

    item = VectorItem.find_by!(label: "unit x")
    assert_equal [1.0, 0.0, 0.0], item.embedding

    item.update!(embedding: [0.5, 0.5, 0.0])
    assert_equal [0.5, 0.5, 0.0], item.reload.embedding
    item.update!(embedding: [1, 0, 0])
  end

  it "dumps vector columns in schema.rb" do
    output = dump_schema
    assert_match(/t\.vector "embedding", limit: 3/, output)
  end

  it "executes each distance operator ordering" do
    {
      l2: ["unit x", "near x"],
      cosine: ["unit x", "big x"],
      ip: ["big x", "near x"]
    }.each do |metric, expected|
      labels = VectorItem.order(VectorItem.paradedb_arel.vector_distance(:embedding, [1, 0, 0], metric: metric).asc)
                         .limit(2)
                         .pluck(:label)
      assert_equal expected, labels, "metric #{metric}"
    end
  end

  it "runs Top-K vector search through the ParadeDB index" do
    skip_unless_vector_index_support!

    conn = ActiveRecord::Base.connection
    conn.remove_paradedb_index(:vector_items, if_exists: true)
    conn.create_paradedb_index(VectorItemIndex)

    labels = VectorItem.nearest(:embedding, [1, 0, 0]).limit(2).pluck(:label)
    assert_equal ["unit x", "near x"], labels

    filtered = VectorItem.search(:label)
                         .match_all("near")
                         .nearest(:embedding, [1, 0, 0])
                         .limit(2)
                         .pluck(:label)
    assert_equal ["near x"], filtered
  ensure
    ActiveRecord::Base.connection.remove_paradedb_index(:vector_items, if_exists: true)
  end

  it "round-trips vector opclasses through the schema dumper" do
    skip_unless_vector_index_support!

    conn = ActiveRecord::Base.connection
    conn.remove_paradedb_index(:vector_items, if_exists: true)

    cosine_index = Class.new(ParadeDB::Index) do
      self.table_name = :vector_items
      self.key_field = :id
      self.fields = { id: {}, label: {}, embedding: { metric: :cosine } }
    end
    conn.create_paradedb_index(cosine_index)

    output = dump_schema
    assert_match(/add_paradedb_index :vector_items,.*embedding: \{ metric: :cosine \}/, output)
  ensure
    ActiveRecord::Base.connection.remove_paradedb_index(:vector_items, if_exists: true)
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end

  def pgvector_available?
    ActiveRecord::Base.connection.select_value(
      "SELECT 1 FROM pg_available_extensions WHERE name = 'vector' LIMIT 1"
    )
  end

  def vector_index_supported?
    ActiveRecord::Base.connection.select_value(<<~SQL)
      SELECT 1
      FROM pg_opclass oc
      JOIN pg_am am ON am.oid = oc.opcmethod
      WHERE am.amname = 'paradedb' AND oc.opcname = 'vector_l2_ops'
      LIMIT 1
    SQL
  end

  def skip_unless_vector_index_support!
    return if vector_index_supported?

    version = ActiveRecord::Base.connection.select_value(
      "SELECT extversion FROM pg_extension WHERE extname = 'pg_search'"
    )
    skip "pg_search #{version} has no vector opclasses for the paradedb access method; " \
         "vector-in-index support requires pg_search 0.25.0+"
  end

  def ensure_vector_schema!
    return if self.class.instance_variable_get(:@vector_schema_done)

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")
    conn.execute("DROP TABLE IF EXISTS vector_items;")

    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :vector_items, force: true do |t|
          t.text :label
          t.vector :embedding, limit: 3
        end
      end
    end

    VectorItem.reset_column_information
    self.class.instance_variable_set(:@vector_schema_done, true)
  end

  def seed_vector_items!
    VectorItem.connection.execute("TRUNCATE TABLE vector_items RESTART IDENTITY;")

    VectorItem.create!(label: "unit x", embedding: [1, 0, 0])
    VectorItem.create!(label: "unit y", embedding: [0, 1, 0])
    VectorItem.create!(label: "near x", embedding: [1.5, 0.5, 0])
    VectorItem.create!(label: "big x", embedding: [8, 1, 0])
  end

  def dump_schema
    io = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)
    io.string
  end
end
