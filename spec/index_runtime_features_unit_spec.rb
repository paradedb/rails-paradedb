# frozen_string_literal: true

require "spec_helper"

RSpec.describe "IndexRuntimeFeaturesUnitTest" do
  before do
    @previous_mode = ParadeDB.index_validation_mode
    ParadeDB.index_validation_mode = :off

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.remove_bm25_index(:products, if_exists: true) if conn.respond_to?(:remove_bm25_index)
  end

  after do
    ParadeDB.index_validation_mode = @previous_mode
    ActiveRecord::Base.connection.remove_bm25_index(:products, if_exists: true) rescue nil
    cleanup_constants("RuntimeProduct", "RuntimeProductIndex", "CustomRuntimeIndex", "ExplicitRuntimeProduct", "DriftProduct", "DriftProductIndex")
  end

  it "validates index_validation_mode values" do
    ParadeDB.index_validation_mode = :warn
    assert_equal :warn, ParadeDB.index_validation_mode

    error = assert_raises(ArgumentError) { ParadeDB.index_validation_mode = :invalid_mode }
    assert_includes error.message, "index_validation_mode must be one of"
  end

  it "paradedb_index macro overrides convention" do
    Object.const_set("CustomRuntimeIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [:id, :description]
    end)

    Object.const_set("ExplicitRuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
      paradedb_index CustomRuntimeIndex
      paradedb_index CustomRuntimeIndex
    end)

    assert_equal CustomRuntimeIndex, ExplicitRuntimeProduct.paradedb_index_class
    assert_equal [CustomRuntimeIndex], ExplicitRuntimeProduct.paradedb_index_classes
  end

  it "search raises FieldNotIndexed for non-indexed fields" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [:id, :description]
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    error = assert_raises(ParadeDB::FieldNotIndexed) { RuntimeProduct.search(:price) }
    assert_includes error.message, "not indexed"
  end

  it "search uses alias cast for aliased index fields" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [
        :id,
        { description: { simple: { alias: "description_simple" } } }
      ]
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    sql = RuntimeProduct.search(:description_simple).matching_all("shoes").to_sql
    assert_includes sql, "::pdb.alias('description_simple')"
  end

  it "raise mode detects missing catalog index drift" do
    Object.const_set("DriftProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("DriftProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.index_name = :products_missing_bm25_idx
      self.fields = [:id, :description]
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
