# frozen_string_literal: true

require "spec_helper"

RSpec.describe "IndexDsl" do
  it "compiles structured hash fields with index_options" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.index_options = { target_segment_count: 17 }
      self.fields = {
        id: {},
        description: {
          tokenizers: [
            ParadeDB::Tokenizer.literal(),
            ParadeDB::Tokenizer.simple(options: {alias: "description_simple", lowercase: true})
          ]
        }
      }
    end

    compiled = klass.compiled_definition
    assert_equal({ target_segment_count: 17 }, compiled.index_options)
    assert_equal 3, compiled.entries.length
    assert_includes compiled.entries.map(&:query_key), "description_simple"
  end

  it "compiles vector index build options and renders them in WITH" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.index_options = { centroid_ratio: 0.01, training_samples_per_centroid: 32, cluster_replication: 2 }
      self.fields = { id: {}, description: nil, embedding: { metric: :cosine } }
    end

    compiled = klass.compiled_definition
    assert_equal(
      { centroid_ratio: 0.01, training_samples_per_centroid: 32, cluster_replication: 2 },
      compiled.index_options
    )

    sql = ActiveRecord::Base.connection.send(:build_create_sql, compiled, if_not_exists: false)
    assert_sql_equal <<~SQL, sql
      CREATE INDEX mock_items_search_idx ON mock_items
      USING paradedb (id, description, embedding vector_cosine_ops)
      WITH (key_field='id', centroid_ratio=0.01, training_samples_per_centroid=32, cluster_replication=2)
    SQL
  end

  it "renders a single vector index build option in WITH" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.index_options = { centroid_ratio: 0.5 }
      self.fields = { id: {}, description: nil }
    end

    sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: false)
    assert_sql_equal <<~SQL, sql
      CREATE INDEX mock_items_search_idx ON mock_items
      USING paradedb (id, description)
      WITH (key_field='id', centroid_ratio=0.5)
    SQL
  end

  it "rejects out-of-range and mistyped vector index build options" do
    build = lambda do |options|
      Class.new(ParadeDB::Index) do
        self.table_name = :mock_items
        self.key_field = :id
        self.index_options = options
        self.fields = { id: {} }
      end
    end

    [{ centroid_ratio: 0.0000001 }, { centroid_ratio: 1.5 }, { centroid_ratio: "0.01" }].each do |options|
      error = assert_raises(ParadeDB::InvalidIndexDefinition) { build.call(options).compiled_definition }
      assert_includes error.message, "centroid_ratio"
      assert_includes error.message, "between 0.000001 and 1.0"
    end

    %i[training_samples_per_centroid cluster_replication].each do |key|
      [0, -1, 1.5, "32"].each do |value|
        error = assert_raises(ParadeDB::InvalidIndexDefinition) { build.call({ key => value }).compiled_definition }
        assert_includes error.message, "index_options[#{key.inspect}] must be an Integer > 0"
      end
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { build.call({ centroid: 0.01 }).compiled_definition }
    assert_includes error.message, "unknown index_options keys"
  end

  it "parses vector index build options back from catalog reloptions" do
    conn = ActiveRecord::Base.connection
    indexdef = <<~SQL.squish
      CREATE INDEX mock_items_search_idx ON public.mock_items
      USING paradedb (id, description, embedding vector_cosine_ops)
      WITH (key_field='id', centroid_ratio='0.01', training_samples_per_centroid='32', cluster_replication='2')
    SQL

    ruby_stmt = conn.send(
      :paradedb_index_to_ruby,
      {
        "indexdef" => indexdef,
        "table_name" => "mock_items",
        "index_name" => "mock_items_search_idx",
        "reloptions" => '["key_field=id","centroid_ratio=0.01","training_samples_per_centroid=32","cluster_replication=2"]'
      }
    )

    assert_equal(
      %(add_paradedb_index :mock_items, fields: { id: {}, description: {}, embedding: { metric: :cosine } }, key_field: :id, name: "mock_items_search_idx", index_options: { :centroid_ratio => 0.01, :training_samples_per_centroid => 32, :cluster_replication => 2 }),
      ruby_stmt
    )
  end

  it "extracts index options from reloptions entries, skipping unknown and malformed values" do
    conn = ActiveRecord::Base.connection

    options = conn.send(
      :extract_paradedb_index_options,
      ["key_field=id", "centroid_ratio=0.01", "training_samples_per_centroid=32", "cluster_replication=2"]
    )
    assert_equal(
      { centroid_ratio: 0.01, training_samples_per_centroid: 32, cluster_replication: 2 },
      options
    )

    assert_equal({}, conn.send(:extract_paradedb_index_options, nil))
    assert_equal({}, conn.send(:extract_paradedb_index_options, "not json"))
    assert_equal(
      {},
      conn.send(
        :extract_paradedb_index_options,
        ["key_field=id", "mystery=1", "centroid_ratio=abc", "training_samples_per_centroid=1.5", "cluster_replication"]
      )
    )
  end

  it "compiles partial index predicates" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.where = "archived_at IS NULL"
      self.fields = {
        id: {},
        description: { tokenizer: ParadeDB::Tokenizer.simple() }
      }
    end

    compiled = klass.compiled_definition

    assert_equal "archived_at IS NULL", compiled.where
    sql = ActiveRecord::Base.connection.send(:build_create_sql, compiled, if_not_exists: false)
    assert_sql_equal <<~SQL, sql
      CREATE INDEX mock_items_search_idx ON mock_items
      USING paradedb (id, (description::pdb.simple))
      WITH (key_field='id')
      WHERE archived_at IS NULL
    SQL
  end

  it "renders concurrent create index SQL" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: ParadeDB::Tokenizer.simple() }
      }
    end

    sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: true, concurrently: true)
    assert_sql_equal <<~SQL, sql
      CREATE INDEX CONCURRENTLY IF NOT EXISTS mock_items_search_idx ON mock_items
      USING paradedb (id, (description::pdb.simple))
      WITH (key_field='id')
    SQL
  end

  it "rejects mixing tokenizers with single tokenizer keys" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: {
          tokenizers: [ParadeDB::Tokenizer.literal()],
          tokenizer: ParadeDB::Tokenizer.simple()
        }
      }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "cannot mix"
  end

  it "rejects non-Tokenizer tokenizer config" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: :simple }
      }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "must be a Tokenizer"
  end

  it "compiles a valid index definition" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: ParadeDB::Tokenizer.simple() },
        category: { tokenizer: ParadeDB::Tokenizer.literal() },
        "metadata->>'title'" => { tokenizer: ParadeDB::Tokenizer.simple(options: {alias: "metadata_title"}) }
      }
    end

    compiled = klass.compiled_definition

    assert_equal :mock_items, compiled.table_name
    assert_equal :id, compiled.key_field
    assert_equal "mock_items_search_idx", compiled.index_name
    assert_operator compiled.entries.length, :>=, 4
  end

  it "requires key_field" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.fields = { id: {} }
    end

    assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
  end

  it "requires alias for ambiguous entries" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: {
          tokenizers: [
            ParadeDB::Tokenizer.simple(),
            ParadeDB::Tokenizer.literal()
          ]
        }
      }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "ambiguous"
    assert_includes error.message, "alias"
  end

  it "allows disambiguated tokenizers with aliases" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: {
          tokenizers: [
            ParadeDB::Tokenizer.simple(options: {alias: "description_simple"}),
            ParadeDB::Tokenizer.literal(options: {alias: "description_exact"})
          ]
        }
      }
    end

    compiled = klass.compiled_definition
    keys = compiled.entries.map(&:query_key)

    assert_includes keys, "description_simple"
    assert_includes keys, "description_exact"
  end

  it "renders ngram tokenizer with min and max arguments" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: ParadeDB::Tokenizer.ngram(2, 5) }
      }
    end

    sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: false)
    assert_sql_equal <<~SQL, sql
      CREATE INDEX mock_items_search_idx ON mock_items
      USING paradedb (id, (description::pdb.ngram(2, 5)))
      WITH (key_field='id')
    SQL
  end

  it "rejects non-Tokenizer values in tokenizers arrays" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizers: [ParadeDB::Tokenizer.literal(), :simple] }
      }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "must be a Tokenizer"
  end

  it "renders custom tokenizer objects" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: ParadeDB::Tokenizer.new("pdb::xyz", nil, nil) },
        "metadata->>'title'" => { tokenizer: ParadeDB::Tokenizer.new("pdb::abc", [12, "fafda"], nil) }
      }
    end

    sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: false)
    assert_sql_equal <<~SQL, sql
      CREATE INDEX mock_items_search_idx ON mock_items
      USING paradedb (id, (description::pdb::xyz), ((metadata->>'title')::pdb::abc(12, 'fafda')))
      WITH (key_field='id')
    SQL
  end

  it "round-trips tokenizer args through schema ruby" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: {
          tokenizer: ParadeDB::Tokenizer.ngram(2, 5, options: {prefix_only: true, alias: "description_ngram"})
        }
      }
    end

    conn = ActiveRecord::Base.connection
    compiled = klass.compiled_definition
    indexdef = conn.send(:build_create_sql, compiled, if_not_exists: false)
    ruby_stmt = conn.send(
      :paradedb_index_to_ruby,
      {
        "indexdef" => indexdef,
        "table_name" => compiled.table_name.to_s,
        "index_name" => compiled.index_name.to_s
      }
    )

    recorder = Class.new do
      attr_reader :captured

      def add_paradedb_index(table, fields:, key_field:, name:, index_options: nil, if_not_exists: false)
        @captured = {
          table: table,
          fields: fields,
          key_field: key_field,
          name: name,
          index_options: index_options,
          if_not_exists: if_not_exists
        }
      end
    end.new

    recorder.instance_eval(ruby_stmt)

    reloaded = Class.new(ParadeDB::Index) do
      self.table_name = recorder.captured[:table]
      self.key_field = recorder.captured[:key_field]
      self.index_name = recorder.captured[:name]
      self.fields = recorder.captured[:fields]
      self.index_options = recorder.captured[:index_options] if recorder.captured[:index_options]
    end

    original_entries = compiled.entries.map { |entry| [entry.source, entry.tokenizer, entry.options, entry.query_key] }
    reloaded_entries = reloaded.compiled_definition.entries.map { |entry| [entry.source, entry.tokenizer, entry.options, entry.query_key] }

    assert_equal original_entries, reloaded_entries
  end

  it "dumps schema ruby as add_paradedb_index" do
    conn = ActiveRecord::Base.connection
    indexdef = <<~SQL.squish
      CREATE INDEX mock_items_search_idx ON public.mock_items
      USING paradedb (id, description)
      WITH (key_field=id)
    SQL

    ruby_stmt = conn.send(
      :paradedb_index_to_ruby,
      {
        "indexdef" => indexdef,
        "table_name" => "mock_items",
        "index_name" => "mock_items_search_idx"
      }
    )

    assert_equal(
      %(add_paradedb_index :mock_items, fields: { id: {}, description: {} }, key_field: :id, name: "mock_items_search_idx"),
      ruby_stmt
    )
  end

  it "exposes the paradedb migration helpers" do
    conn = ActiveRecord::Base.connection

    %i[add_paradedb_index remove_paradedb_index reindex_paradedb_index].each do |helper|
      assert conn.respond_to?(helper)
      assert ParadeDB::MigrationDSL.method_defined?(helper)
    end
  end

  it "inverts index helpers to paradedb-named commands in the command recorder" do
    recorder = ActiveRecord::Migration::CommandRecorder.new(ActiveRecord::Base.connection)

    method, args = recorder.inverse_of(:add_paradedb_index, [:mock_items, { key_field: :id, name: :mock_items_alias_idx }])
    assert_equal :remove_paradedb_index, method
    assert_equal :mock_items, args.first
    assert_equal({ if_exists: true, name: :mock_items_alias_idx }, args.last)

    %i[remove_paradedb_index reindex_paradedb_index].each do |command|
      assert_raises(ActiveRecord::IrreversibleMigration) do
        recorder.inverse_of(command, [:mock_items])
      end
    end
  end

  # ---- vector fields ----

  def vector_index_klass(metric: :cosine)
    Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.index_name = :mock_items_vector_search_idx
      self.fields = { id: {}, description: nil, embedding: { metric: metric } }
    end
  end

  it "compiles vector fields with a metric" do
    compiled = vector_index_klass.compiled_definition
    entry = compiled.entries.find { |e| e.source == "embedding" }

    assert_equal :cosine, entry.metric
    assert_nil entry.tokenizer
    assert_equal "embedding", entry.query_key
  end

  it "emits vector opclasses in index DDL" do
    sql = ActiveRecord::Base.connection.send(
      :build_create_sql, vector_index_klass.compiled_definition, if_not_exists: false
    )

    assert_sql_equal <<~SQL, sql
      CREATE INDEX mock_items_vector_search_idx ON mock_items
      USING paradedb (id, description, embedding vector_cosine_ops)
      WITH (key_field='id')
    SQL
  end

  it "emits each metric opclass" do
    { l2: "vector_l2_ops", cosine: "vector_cosine_ops", ip: "vector_ip_ops" }.each do |metric, opclass|
      klass = vector_index_klass(metric: metric)
      sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: false)
      assert_includes normalize_sql(sql), "embedding #{opclass}"
    end
  end

  it "rejects unknown index metrics" do
    klass = vector_index_klass(metric: :manhattan)

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "unknown vector metric"
  end

  it "rejects metric combined with other field config" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = { id: {}, embedding: { metric: :l2, tokenizer: ParadeDB::Tokenizer.simple() } }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "cannot mix :metric"
  end

  it "round-trips vector opclasses through schema ruby" do
    conn = ActiveRecord::Base.connection
    compiled = vector_index_klass.compiled_definition
    indexdef = conn.send(:build_create_sql, compiled, if_not_exists: false)
    ruby_stmt = conn.send(
      :paradedb_index_to_ruby,
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

  it "parses vector opclass columns back to metric fields" do
    conn = ActiveRecord::Base.connection
    indexdef = <<~SQL.squish
      CREATE INDEX vsp_idx ON public.vsp
      USING paradedb (id, label, vec vector_l2_ops)
      WITH (key_field='id')
    SQL

    ruby_stmt = conn.send(
      :paradedb_index_to_ruby,
      { "indexdef" => indexdef, "table_name" => "vsp", "index_name" => "vsp_idx" }
    )

    assert_includes ruby_stmt, "vec: { metric: :l2 }"
    assert_includes ruby_stmt, "label: {}"
  end

  # ---- vector column type ----

  it "reports the vector type" do
    type = ParadeDB::Vector.new
    assert_equal :vector, type.type
    assert_nil type.limit
    assert_equal 3, ParadeDB::Vector.new(limit: 3).limit
  end

  it "is registered in the postgresql adapter type map" do
    map = ActiveRecord::Type::HashLookupTypeMap.new
    ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.initialize_type_map(map)

    resolved = map.lookup("vector", nil, "vector(3)")
    assert_instance_of ParadeDB::Vector, resolved
    assert_equal 3, resolved.limit

    unlimited = map.lookup("vector", nil, "vector")
    assert_nil unlimited.limit
  end

  it "casts arrays and pgvector literals to floats" do
    type = ParadeDB::Vector.new
    assert_equal [1.0, 2.0, 3.0], type.cast([1, 2, 3])
    assert_equal [1.5, -2.25], type.cast(["1.5", "-2.25"])
    assert_nil type.cast(nil)
    assert_equal [1.0, 2.0, 3.0], type.cast("[1,2,3]")
    assert_equal [0.25, -1.0], type.cast(" [0.25, -1] ")
  end

  it "rejects malformed and uncastable vector values" do
    type = ParadeDB::Vector.new

    error = assert_raises(ArgumentError) { type.cast("1,2,3") }
    assert_includes error.message, "malformed vector literal"

    error = assert_raises(ArgumentError) { type.cast(1.0) }
    assert_includes error.message, "cannot cast"
  end

  it "serializes and deserializes pgvector text form" do
    type = ParadeDB::Vector.new
    assert_equal "[1.0,2.0,3.0]", type.serialize([1, 2, 3])
    assert_equal "[1.0,2.0,3.0]", type.serialize("[1,2,3]")
    assert_nil type.serialize(nil)
    assert_equal [1.0, 2.0, 3.0], type.deserialize("[1,2,3]")
  end

  it "validates vector dimensions against the limit" do
    limited = ParadeDB::Vector.new(limit: 3)
    assert_equal [1.0, 2.0, 3.0], limited.cast([1, 2, 3])

    error = assert_raises(ArgumentError) { limited.cast([1, 2]) }
    assert_includes error.message, "expected 3 dimensions, got 2"
  end

  it "detects in-place vector changes" do
    type = ParadeDB::Vector.new
    assert type.changed_in_place?("[1,2,3]", [1.0, 2.0, 4.0])
    assert_not type.changed_in_place?("[1,2,3]", [1.0, 2.0, 3.0])
  end

  it "renders vector(n) in DDL type SQL" do
    conn = ActiveRecord::Base.connection
    assert_equal "vector(3)", conn.type_to_sql(:vector, limit: 3)
    assert_equal "vector", conn.type_to_sql(:vector)
    assert conn.valid_type?(:vector)
  end

  it "exposes t.vector in table definitions" do
    assert ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.method_defined?(:vector)
  end

  it "normalizes vector metrics" do
    assert_equal :l2, ParadeDB::Vector.normalize_metric(:l2)
    assert_equal :cosine, ParadeDB::Vector.normalize_metric("cosine")
    assert_equal :ip, ParadeDB::Vector.normalize_metric(:ip)
    assert_equal :ip, ParadeDB::Vector.normalize_metric(:inner_product)

    error = assert_raises(ArgumentError) { ParadeDB::Vector.normalize_metric(:manhattan) }
    assert_includes error.message, "unknown vector metric"
  end

  it "builds pgvector literals" do
    assert_equal "[1.0,2.0,3.0]", ParadeDB::Vector.literal([1, 2, 3])
  end
end


RSpec.describe "IndexRuntimeFeatures" do
  before do
    @previous_mode = ParadeDB.index_validation_mode
    ParadeDB.index_validation_mode = :off

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search CASCADE;")
    conn.remove_paradedb_index(:mock_items, if_exists: true) if conn.respond_to?(:remove_paradedb_index)
  end

  after do
    ParadeDB.index_validation_mode = @previous_mode
    ActiveRecord::Base.connection.remove_paradedb_index(:mock_items, if_exists: true) rescue nil
    cleanup_constants("RuntimeProduct", "RuntimeProductIndex", "CustomRuntimeIndex", "ExplicitRuntimeProduct", "DriftProduct", "DriftProductIndex")
  end

  it "validates index_validation_mode values" do
    ParadeDB.index_validation_mode = :warn
    assert_equal :warn, ParadeDB.index_validation_mode

    error = assert_raises(ArgumentError) { ParadeDB.index_validation_mode = :invalid_mode }
    assert_includes error.message, "index_validation_mode must be one of"

    error = assert_raises(ArgumentError) { ParadeDB.index_validation_mode = nil }
    assert_includes error.message, "index_validation_mode must be one of"

    error = assert_raises(ArgumentError) { ParadeDB.index_validation_mode = " " }
    assert_includes error.message, "index_validation_mode must be one of"
  end

  it "paradedb_index macro overrides convention" do
    Object.const_set("CustomRuntimeIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = { id: {}, description: {} }
    end)

    Object.const_set("ExplicitRuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
      paradedb_index CustomRuntimeIndex
      paradedb_index CustomRuntimeIndex
    end)

    assert_equal CustomRuntimeIndex, ExplicitRuntimeProduct.paradedb_index_class
    assert_equal [CustomRuntimeIndex], ExplicitRuntimeProduct.paradedb_index_classes
  end

  it "search raises FieldNotIndexed for non-indexed fields" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = { id: {}, description: {} }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    error = assert_raises(ParadeDB::FieldNotIndexed) { RuntimeProduct.search(:rating) }
    assert_includes error.message, "not indexed"
  end

  it "relation search raises FieldNotIndexed for non-indexed fields" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = { id: {}, description: {} }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    error = assert_raises(ParadeDB::FieldNotIndexed) do
      RuntimeProduct.search(:description).search(:rating)
    end
    assert_includes error.message, "not indexed"
  end

  it "search uses alias cast for aliased index fields" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        category: {},
        description: { tokenizer: ParadeDB::Tokenizer.simple(options: {alias: "description_simple"}) }
      }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    sql = RuntimeProduct.search(:description_simple).match_all("shoes").to_sql
    assert_includes sql, "::pdb.alias('description_simple')"
  end

  it "relation search uses alias cast for aliased index fields" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        category: {},
        description: { tokenizer: ParadeDB::Tokenizer.simple(options: {alias: "description_simple"}) }
      }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    sql = RuntimeProduct.search(:category).search(:description_simple).match_all("shoes").to_sql
    assert_includes sql, "::pdb.alias('description_simple')"
  end

  it "aggregate_by rejects text fields without a literal tokenizer" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        category: {}
      }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    error = assert_raises(ParadeDB::InvalidIndexDefinition) do
      RuntimeProduct.aggregate_by(:category, agg: ParadeDB::Aggregations.value_count(:id)).to_sql
    end

    assert_includes error.message, ":literal"
    assert_includes error.message, "category"
  end

  it "aggregate_by rejects aliased text fields with a non-literal tokenizer" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: ParadeDB::Tokenizer.simple(options: {alias: "description_simple"}) }
      }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    error = assert_raises(ParadeDB::InvalidIndexDefinition) do
      RuntimeProduct.aggregate_by(:description_simple, agg: ParadeDB::Aggregations.value_count(:id)).to_sql
    end

    assert_includes error.message, "description_simple"
    assert_includes error.message, ":literal"
  end

  it "aggregate_by resolves literal-tokenized aliased fields to the indexed source column" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: ParadeDB::Tokenizer.literal(options: {alias: "description_exact"}) }
      }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    sql = RuntimeProduct.aggregate_by(:description_exact, agg: ParadeDB::Aggregations.value_count(:id)).to_sql
    assert_includes sql, %("mock_items"."description")
    refute_includes sql, %("mock_items"."description_exact")
  end

  it "filtered with_agg resolves aliased fields to a search alias cast" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: ParadeDB::Tokenizer.simple(options: {alias: "description_simple"}) }
      }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    sql = RuntimeProduct.with_agg(
      hits: ParadeDB::Aggregations.filtered(
        ParadeDB::Aggregations.value_count(:id),
        field: :description_simple,
        term: "shoes"
      )
    ).to_sql

    assert_includes sql, "::pdb.alias('description_simple')"
    refute_includes sql, %("mock_items"."description_simple" === 'shoes')
  end

  it "filtered facets_agg resolves aliased fields against the aggregation source alias" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: ParadeDB::Tokenizer.simple(options: {alias: "description_simple"}) }
      }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    relation = RuntimeProduct.search(:id).match_all
    sql = relation.send(
      :build_aggregation_query,
      relation.send(
        :normalize_named_aggregation_specs,
        hits: ParadeDB::Aggregations.filtered(
          ParadeDB::Aggregations.value_count(:id),
          field: :description_simple,
          term: "shoes"
        )
      )
    ).sql

    assert_includes sql, "::pdb.alias('description_simple')"
    refute_includes sql, %("paradedb_agg_source"."description_simple" === 'shoes')
  end

  it "facets raises FieldNotIndexed for non-indexed facet fields" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.fields = { id: {}, description: {} }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    error = assert_raises(ParadeDB::FieldNotIndexed) do
      RuntimeProduct.search(:description).match_all("shoe").build_facet_query(fields: [:rating]).sql
    end
    assert_includes error.message, "non-indexed fields"
  end

  it "raise mode detects missing catalog index drift" do
    Object.const_set("DriftProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :mock_items
      include ParadeDB::Model
    end)
    Object.const_set("DriftProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :mock_items
      self.key_field = :id
      self.index_name = :mock_items_missing_search_idx
      self.fields = { id: {}, description: {} }
    end)

    ParadeDB.index_validation_mode = :raise
    error = assert_raises(ParadeDB::IndexDriftError) { DriftProduct.paradedb_validate_index! }
    assert_includes error.message, "drift detected"
  end

  private

  def cleanup_constants(*names)
    names.each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
  end
end
