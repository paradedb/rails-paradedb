# frozen_string_literal: true

require "spec_helper"

class VectorPlainProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products
end

class VectorSearchProductIndex < ParadeDB::Index
  self.table_name = :products
  self.key_field = :id
  self.index_name = :vector_search_products_bm25_idx
  self.fields = {
    id: {},
    description: nil,
    embedding: { metric: :cosine }
  }
end

class VectorIndexedProduct < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :products

  paradedb_index VectorSearchProductIndex
end

RSpec.describe "VectorSearchUnitTest" do
  before do
    @builder = ParadeDB::Arel::Builder.new(:products)
  end

  def sql(node)
    ParadeDB::Arel.to_sql(node)
  end

  # ---- Builder distance expressions ----

  it "renders l2 distance" do
    node = @builder.l2_distance(:embedding, [1, 2, 3])
    assert_equal %("products"."embedding" <-> '[1.0,2.0,3.0]'::vector), sql(node)
  end

  it "renders cosine distance" do
    node = @builder.cosine_distance(:embedding, [1, 2, 3])
    assert_equal %("products"."embedding" <=> '[1.0,2.0,3.0]'::vector), sql(node)
  end

  it "renders inner product" do
    node = @builder.inner_product(:embedding, [1, 2, 3])
    assert_equal %("products"."embedding" <#> '[1.0,2.0,3.0]'::vector), sql(node)
  end

  it "dispatches vector_distance by metric" do
    assert_includes sql(@builder.vector_distance(:embedding, [1.0], metric: :l2)), "<->"
    assert_includes sql(@builder.vector_distance(:embedding, [1.0], metric: :cosine)), "<=>"
    assert_includes sql(@builder.vector_distance(:embedding, [1.0], metric: :ip)), "<#>"
    assert_includes sql(@builder.vector_distance(:embedding, [1.0], metric: :inner_product)), "<#>"
    assert_includes sql(@builder.vector_distance(:embedding, [1.0])), "<->"
  end

  it "rejects unknown metrics" do
    error = assert_raises(ArgumentError) { @builder.vector_distance(:embedding, [1.0], metric: :manhattan) }
    assert_includes error.message, "unknown vector metric"
  end

  it "quotes string vector operands" do
    node = @builder.l2_distance(:embedding, "[1,2,3]")
    assert_equal %("products"."embedding" <-> '[1,2,3]'::vector), sql(node)
  end

  it "quotes malicious vector operands safely" do
    node = @builder.l2_distance(:embedding, "[1]'; DROP TABLE products; --")
    assert_includes sql(node), %('[1]''; DROP TABLE products; --'::vector)
  end

  it "passes arel operands through untouched" do
    node = @builder.l2_distance(:embedding, ::Arel.sql("$1"))
    assert_equal %("products"."embedding" <-> $1), sql(node)
  end

  # ---- Predications ----

  it "exposes distance predications on attributes" do
    attr = VectorPlainProduct.arel_table[:embedding]
    assert_equal %("products"."embedding" <-> '[1.0]'::vector), sql(attr.pdb_l2_distance([1]))
    assert_equal %("products"."embedding" <=> '[1.0]'::vector), sql(attr.pdb_cosine_distance([1]))
    assert_equal %("products"."embedding" <#> '[1.0]'::vector), sql(attr.pdb_inner_product([1]))
    assert_equal %("products"."embedding" <=> '[1.0]'::vector), sql(attr.pdb_vector_distance([1], metric: :cosine))
  end

  # ---- Relation API ----

  it "nearest adds match-all predicate and distance ordering" do
    sql = VectorPlainProduct.nearest(:embedding, [1, 2, 3]).limit(2).to_sql

    assert_includes sql, %(("products"."id" @@@ pdb.all()))
    assert_includes sql, %(ORDER BY "products"."embedding" <-> '[1.0,2.0,3.0]'::vector ASC)
    assert_includes sql, "LIMIT"
  end

  it "nearest respects explicit metric" do
    sql = VectorPlainProduct.nearest(:embedding, [1, 2, 3], metric: :ip).limit(2).to_sql
    assert_includes sql, %("products"."embedding" <#> '[1.0,2.0,3.0]'::vector ASC)
  end

  it "nearest defaults the metric from the index definition" do
    sql = VectorIndexedProduct.nearest(:embedding, [1, 2, 3]).limit(2).to_sql
    assert_includes sql, %("products"."embedding" <=> '[1.0,2.0,3.0]'::vector ASC)
  end

  it "nearest preserves existing paradedb predicates" do
    sql = VectorPlainProduct.search(:description)
                             .match_all("shoes")
                             .nearest(:embedding, [1, 2, 3], metric: :l2)
                             .limit(2)
                             .to_sql

    assert_includes sql, "&&& 'shoes'"
    refute_includes sql, "pdb.all()"
    assert_includes sql, %("products"."embedding" <-> '[1.0,2.0,3.0]'::vector ASC)
  end

  it "nearest chains with standard relation filters" do
    sql = VectorPlainProduct.where(in_stock: true).extending(ParadeDB::SearchMethods)
                            .nearest(:embedding, [1, 2, 3]).limit(5).to_sql

    assert_includes sql, %("products"."in_stock")
    assert_includes sql, %(("products"."id" @@@ pdb.all()))
  end

  # ---- Index DSL and DDL ----

  it "compiles vector fields with a metric" do
    compiled = VectorSearchProductIndex.compiled_definition
    entry = compiled.entries.find { |e| e.source == "embedding" }

    assert_equal :cosine, entry.metric
    assert_nil entry.tokenizer
    assert_equal "embedding", entry.query_key
  end

  it "emits opclasses in index DDL" do
    sql = ActiveRecord::Base.connection.send(
      :build_create_sql, VectorSearchProductIndex.compiled_definition, if_not_exists: false
    )

    assert_sql_equal <<~SQL, sql
      CREATE INDEX vector_search_products_bm25_idx ON products
      USING paradedb (id, description, embedding vector_cosine_ops)
      WITH (key_field='id')
    SQL
  end

  it "emits each metric opclass" do
    { l2: "vector_l2_ops", cosine: "vector_cosine_ops", ip: "vector_ip_ops" }.each do |metric, opclass|
      klass = Class.new(ParadeDB::Index) do
        self.table_name = :products
        self.key_field = :id
        self.fields = { id: {}, embedding: { metric: metric } }
      end

      sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: false)
      assert_includes normalize_sql(sql), "embedding #{opclass}"
    end
  end

  it "rejects unknown index metrics" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = { id: {}, embedding: { metric: :manhattan } }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "unknown vector metric"
  end

  it "rejects metric combined with other field config" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = { id: {}, embedding: { metric: :l2, tokenizer: ParadeDB::Tokenizer.simple() } }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "cannot mix :metric"
  end

  # ---- Schema dump round trip ----

  it "round-trips vector opclasses through schema ruby" do
    conn = ActiveRecord::Base.connection
    compiled = VectorSearchProductIndex.compiled_definition
    indexdef = conn.send(:build_create_sql, compiled, if_not_exists: false)
    ruby_stmt = conn.send(
      :bm25_index_to_ruby,
      {
        "indexdef" => indexdef,
        "table_name" => compiled.table_name.to_s,
        "index_name" => compiled.index_name.to_s
      }
    )

    assert_includes ruby_stmt, "embedding: { metric: :cosine }"

    recorder = Class.new do
      attr_reader :captured

      def add_paradedb_index(table, fields:, key_field:, name:, **)
        @captured = { table: table, fields: fields, key_field: key_field, name: name }
      end
    end.new
    recorder.instance_eval(ruby_stmt)

    reloaded = Class.new(ParadeDB::Index) do
      self.table_name = recorder.captured[:table]
      self.key_field = recorder.captured[:key_field]
      self.index_name = recorder.captured[:name]
      self.fields = recorder.captured[:fields]
    end

    original = compiled.entries.map { |e| [e.source, e.tokenizer, e.query_key, e.metric] }
    round_tripped = reloaded.compiled_definition.entries.map { |e| [e.source, e.tokenizer, e.query_key, e.metric] }
    assert_equal original, round_tripped
  end

  it "parses default opclass columns as plain fields" do
    conn = ActiveRecord::Base.connection
    indexdef = <<~SQL.squish
      CREATE INDEX vsp_idx ON public.vsp
      USING paradedb (id, label, vec vector_l2_ops)
      WITH (key_field='id')
    SQL

    ruby_stmt = conn.send(
      :bm25_index_to_ruby,
      { "indexdef" => indexdef, "table_name" => "vsp", "index_name" => "vsp_idx" }
    )

    assert_includes ruby_stmt, "vec: { metric: :l2 }"
    assert_includes ruby_stmt, "label: {}"
  end
end
