# frozen_string_literal: true

require "spec_helper"

RSpec.describe "IndexDslUnitTest" do
  it "compiles structured hash fields with index_options" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.index_options = { target_segment_count: 17 }
      self.fields = {
        id: {},
        description: {
          tokenizers: [
            { tokenizer: :literal },
            { tokenizer: :simple, alias: "description_simple", filters: [:lowercase] }
          ]
        }
      }
    end

    compiled = klass.compiled_definition
    assert_equal({ target_segment_count: 17 }, compiled.index_options)
    assert_equal 3, compiled.entries.length
    assert_includes compiled.entries.map(&:query_key), "description_simple"
  end

  it "rejects mixing tokenizers with single tokenizer keys" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: {
          tokenizers: [{ tokenizer: :literal }],
          tokenizer: :simple
        }
      }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "cannot mix"
  end

  it "rejects tokenizer config without tokenizer key" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: { filters: [:lowercase] }
      }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "no :tokenizer"
  end

  it "compiles a valid index definition" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [
        :id,
        { description: :simple },
        { category: { literal: {} } },
        { "metadata->>'title'" => { simple: { alias: "metadata_title" } } }
      ]
    end

    compiled = klass.compiled_definition

    assert_equal :products, compiled.table_name
    assert_equal :id, compiled.key_field
    assert_equal "products_bm25_idx", compiled.index_name
    assert_operator compiled.entries.length, :>=, 4
  end

  it "requires key_field" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.fields = [:id]
    end

    assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
  end

  it "requires alias for ambiguous entries" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [
        :id,
        { description: :simple },
        { description: :literal }
      ]
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "ambiguous"
    assert_includes error.message, "alias"
  end

  it "allows disambiguated tokenizers with aliases" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [
        :id,
        { description: { simple: { alias: "description_simple" }, literal: { alias: "description_exact" } } }
      ]
    end

    compiled = klass.compiled_definition
    keys = compiled.entries.map(&:query_key)

    assert_includes keys, "description_simple"
    assert_includes keys, "description_exact"
  end

  it "renders ngram tokenizer with min and max arguments" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [
        :id,
        { description: { ngram: { min: 2, max: 5 } } }
      ]
    end

    sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: false)
    assert_includes sql, "pdb.ngram(2, 5)"
  end

  it "renders qualified and inline tokenizer forms" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [
        :id,
        { description: { "pdb::xyz" => {} } },
        { "metadata->>'title'" => { "pdb::abc(12, \"fafda\")" => {} } }
      ]
    end

    sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: false)
    assert_includes sql, "::pdb::xyz"
    assert_includes sql, "::pdb::abc(12, \"fafda\")"
  end
end
