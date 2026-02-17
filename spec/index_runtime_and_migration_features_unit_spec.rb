# frozen_string_literal: true

require "spec_helper"
require "stringio"

class PendingFeaturesUnitTest < Minitest::Test
  def setup
    @previous_mode = ParadeDB.index_validation_mode
    ParadeDB.index_validation_mode = :warn

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.remove_bm25_index(:products, if_exists: true) if conn.respond_to?(:remove_bm25_index)
  end

  def teardown
    ParadeDB.index_validation_mode = @previous_mode
    cleanup_constants(
      "AutoIndexedProduct", "AutoIndexedProductIndex",
      "SchemaDumpProductIndex",
      "DriftProduct", "DriftProductIndex",
      "ExplicitProduct", "CustomProductIndex",
      "MultiIndexProduct", "MultiProductIndexV1", "MultiProductIndexV2"
    )
  end

  def test_key_field_sql_is_escaped
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = "user'id"
      self.fields = ["user'id", :description]
    end

    sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: false)
    assert_includes sql, "key_field='user''id'"
  end

  def test_key_field_must_be_first_in_fields
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [:description, :id]
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "first"
  end

  def test_key_field_must_not_be_tokenized
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [{ id: :simple }, :description]
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "tokenized"
  end

  def test_convention_resolver_and_metadata_without_explicit_include
    Object.const_set("AutoIndexedProduct", Class.new(ActiveRecord::Base) { self.table_name = :products })
    Object.const_set("AutoIndexedProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [:id, :description]
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(AutoIndexedProductIndex)

    assert_respond_to AutoIndexedProduct, :search
    assert_equal :id, AutoIndexedProduct.paradedb_key_field
    assert_equal "products_bm25_idx", AutoIndexedProduct.paradedb_index_name
    assert_includes AutoIndexedProduct.paradedb_indexed_fields, "description"
  end

  def test_search_raises_for_non_indexed_field
    Object.const_set("AutoIndexedProduct", Class.new(ActiveRecord::Base) { self.table_name = :products })
    Object.const_set("AutoIndexedProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [:id, :description]
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(AutoIndexedProductIndex)

    error = assert_raises(ParadeDB::FieldNotIndexed) do
      AutoIndexedProduct.search(:price)
    end
    assert_includes error.message, "not indexed"
  end

  def test_search_uses_alias_cast_for_aliased_index_field
    Object.const_set("AutoIndexedProduct", Class.new(ActiveRecord::Base) { self.table_name = :products })
    Object.const_set("AutoIndexedProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [
        :id,
        { description: { simple: { alias: "description_simple" } } }
      ]
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(AutoIndexedProductIndex)

    sql = AutoIndexedProduct.search(:description_simple).matching_all("shoes").to_sql
    assert_includes sql, "::pdb.alias('description_simple')"
  end

  def test_raise_mode_detects_catalog_drift
    Object.const_set("DriftProduct", Class.new(ActiveRecord::Base) { self.table_name = :products })
    Object.const_set("DriftProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.index_name = :products_missing_bm25_idx
      self.fields = [:id, :description]
    end)

    ParadeDB.index_validation_mode = :raise
    error = assert_raises(ParadeDB::IndexDriftError) { DriftProduct.paradedb_validate_index! }
    assert_includes error.message, "missing"
  end

  def test_reindex_bm25_helper_exists_and_generates_sql
    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [:id, :description]
    end, if_not_exists: true)

    assert_respond_to conn, :reindex_bm25
    conn.reindex_bm25(:products)
  end

  def test_reindex_bm25_concurrently_rejects_open_transaction
    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [:id, :description]
    end, if_not_exists: true)

    error = assert_raises(ArgumentError) do
      conn.transaction do
        conn.reindex_bm25(:products, concurrently: true)
      end
    end

    assert_includes error.message, "cannot run inside a transaction"
  end

  def test_create_paradedb_index_accepts_index_class_name_string
    Object.const_set("SchemaDumpProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [:id, :description]
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index("SchemaDumpProductIndex", if_not_exists: true)

    assert_includes conn.paradedb_schema_index_references, "SchemaDumpProductIndex"
  end

  def test_schema_dump_from_catalog_without_in_memory_state
    conn = ActiveRecord::Base.connection
    conn.add_bm25_index(:products, fields: [:id, :description], key_field: :id, if_not_exists: true)

    conn.instance_variable_set(:@paradedb_schema_index_references, [])

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    assert_includes stream.string, "add_bm25_index"
    assert_includes stream.string, "products"
    assert_includes stream.string, "key_field"
  end

  def test_schema_dump_does_not_duplicate_bm25_as_add_index
    conn = ActiveRecord::Base.connection
    conn.add_bm25_index(:products, fields: [:id, :description], key_field: :id, if_not_exists: true)

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    schema = stream.string

    assert_includes schema, "add_bm25_index"
    refute_match(/add_index.*products_bm25_idx/, schema)
    refute_match(/t\.index.*products_bm25_idx/, schema)
  end

  def test_paradedb_index_macro_overrides_convention
    Object.const_set("CustomProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [:id, :description]
    end)

    Object.const_set("ExplicitProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      paradedb_index CustomProductIndex
    end)

    assert_equal CustomProductIndex, ExplicitProduct.paradedb_index_class
    assert_equal [CustomProductIndex], ExplicitProduct.paradedb_index_classes
  end

  def test_paradedb_index_macro_supports_multiple_indexes
    Object.const_set("MultiProductIndexV1", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.index_name = :products_v1_idx
      self.fields = [:id, :description]
    end)

    Object.const_set("MultiProductIndexV2", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.index_name = :products_v2_idx
      self.fields = [:id, :description, :category]
    end)

    Object.const_set("MultiIndexProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      paradedb_index MultiProductIndexV1
      paradedb_index MultiProductIndexV2
    end)

    assert_equal [MultiProductIndexV1, MultiProductIndexV2], MultiIndexProduct.paradedb_index_classes
    assert_equal MultiProductIndexV1, MultiIndexProduct.paradedb_index_class
  end

  def test_paradedb_index_macro_does_not_duplicate
    Object.const_set("CustomProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [:id, :description]
    end)

    Object.const_set("ExplicitProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      paradedb_index CustomProductIndex
      paradedb_index CustomProductIndex
    end)

    assert_equal [CustomProductIndex], ExplicitProduct.paradedb_index_classes
  end

  def test_schema_dump_with_tokenized_fields
    Object.const_set("SchemaDumpProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [
        :id,
        { description: :simple }
      ]
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(SchemaDumpProductIndex, if_not_exists: true)

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    schema = stream.string

    assert_includes schema, "add_bm25_index"
    assert_includes schema, "pdb.simple"
  end

  private

  def cleanup_constants(*names)
    names.each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
  end
end
