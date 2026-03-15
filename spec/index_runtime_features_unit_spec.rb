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

    error = assert_raises(ArgumentError) { ParadeDB.index_validation_mode = nil }
    assert_includes error.message, "index_validation_mode must be one of"

    error = assert_raises(ArgumentError) { ParadeDB.index_validation_mode = " " }
    assert_includes error.message, "index_validation_mode must be one of"
  end

  it "paradedb_index macro overrides convention" do
    Object.const_set("CustomRuntimeIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = { id: {}, description: {} }
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
      self.fields = { id: {}, description: {} }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    error = assert_raises(ParadeDB::FieldNotIndexed) { RuntimeProduct.search(:price) }
    assert_includes error.message, "not indexed"
  end

  it "relation search raises FieldNotIndexed for non-indexed fields" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = { id: {}, description: {} }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    error = assert_raises(ParadeDB::FieldNotIndexed) do
      RuntimeProduct.search(:description).search(:price)
    end
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
      self.fields = {
        id: {},
        category: {},
        description: { tokenizer: :simple, alias: "description_simple" }
      }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    sql = RuntimeProduct.search(:description_simple).matching_all("shoes").to_sql
    assert_includes sql, "::pdb.alias('description_simple')"
  end

  it "relation search uses alias cast for aliased index fields" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        category: {},
        description: { tokenizer: :simple, alias: "description_simple" }
      }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    sql = RuntimeProduct.search(:category).search(:description_simple).matching_all("shoes").to_sql
    assert_includes sql, "::pdb.alias('description_simple')"
  end

  it "aggregate_by rejects text fields without a literal tokenizer" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
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
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: :simple, alias: "description_simple" }
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
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: :literal, alias: "description_exact" }
      }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    sql = RuntimeProduct.aggregate_by(:description_exact, agg: ParadeDB::Aggregations.value_count(:id)).to_sql
    assert_includes sql, %("products"."description")
    refute_includes sql, %("products"."description_exact")
  end

  it "filtered with_agg resolves aliased fields to a search alias cast" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: :simple, alias: "description_simple" }
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
    refute_includes sql, %("products"."description_simple" === 'shoes')
  end

  it "filtered facets_agg resolves aliased fields against the aggregation source alias" do
    Object.const_set("RuntimeProduct", Class.new(ActiveRecord::Base) do
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: :simple, alias: "description_simple" }
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
      self.table_name = :products
      include ParadeDB::Model
    end)
    Object.const_set("RuntimeProductIndex", Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = { id: {}, description: {} }
    end)

    conn = ActiveRecord::Base.connection
    conn.create_paradedb_index(RuntimeProductIndex, if_not_exists: true)

    error = assert_raises(ParadeDB::FieldNotIndexed) do
      RuntimeProduct.search(:description).matching_all("shoe").build_facet_query(fields: [:price]).sql
    end
    assert_includes error.message, "non-indexed fields"
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
