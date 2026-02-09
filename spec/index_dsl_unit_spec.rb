# frozen_string_literal: true

require "spec_helper"

class IndexDslUnitTest < Minitest::Test
  class ValidProductIndex < ParadeDB::Index
    self.table_name = :products
    self.key_field = :id
    self.fields = [
      :id,
      { description: :simple },
      { category: { literal: {} } },
      { "metadata->>'title'" => { simple: { alias: "metadata_title" } } }
    ]
  end

  def test_compiles_valid_index_definition
    compiled = ValidProductIndex.compiled_definition

    assert_equal :products, compiled.table_name
    assert_equal :id, compiled.key_field
    assert_equal "products_bm25_idx", compiled.index_name
    assert_operator compiled.entries.length, :>=, 4
  end

  def test_requires_key_field
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.fields = [:id]
    end

    assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
  end

  def test_requires_alias_for_ambiguous_entries
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

  def test_allows_disambiguated_multiple_tokenizers_with_alias
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

  def test_extended_lindera_language_variants_generate_sql
    %w[chinese japanese korean thai].each do |language|
      klass = Class.new(ParadeDB::Index) do
        self.table_name = :products
        self.key_field = :id
        self.fields = [
          :id,
          { description: { lindera: language.to_sym } }
        ]
      end

      sql = ActiveRecord::Base.connection.send(
        :build_create_sql,
        klass.compiled_definition,
        if_not_exists: false
      )

      assert_includes sql, "pdb.lindera(#{language})"
    end
  end

  def test_extended_ngram_min_max_generate_sql
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [
        :id,
        { description: { ngram: { min: 2, max: 5 } } }
      ]
    end

    sql = ActiveRecord::Base.connection.send(
      :build_create_sql,
      klass.compiled_definition,
      if_not_exists: false
    )

    assert_includes sql, "pdb.ngram(2, 5)"
  end

  def test_extended_qualified_and_inline_tokenizer_forms_generate_sql
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = [
        :id,
        { description: { "pdb::xyz" => {} } },
        { "metadata->>'title'" => { "pdb::abc(12, \"fafda\")" => {} } }
      ]
    end

    sql = ActiveRecord::Base.connection.send(
      :build_create_sql,
      klass.compiled_definition,
      if_not_exists: false
    )

    assert_includes sql, "::pdb::xyz"
    assert_includes sql, "::pdb::abc(12, \"fafda\")"
  end
end
