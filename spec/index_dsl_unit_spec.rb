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
            Tokenizer.literal(),
            Tokenizer.simple(options: {alias: "description_simple", lowercase: true})
          ]
        }
      }
    end

    compiled = klass.compiled_definition
    assert_equal({ target_segment_count: 17 }, compiled.index_options)
    assert_equal 3, compiled.entries.length
    assert_includes compiled.entries.map(&:query_key), "description_simple"
  end

  it "compiles partial index predicates" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.where = "archived_at IS NULL"
      self.fields = {
        id: {},
        description: { tokenizer: Tokenizer.simple() }
      }
    end

    compiled = klass.compiled_definition

    assert_equal "archived_at IS NULL", compiled.where
    sql = ActiveRecord::Base.connection.send(:build_create_sql, compiled, if_not_exists: false)
    assert_sql_equal <<~SQL, sql
      CREATE INDEX products_bm25_idx ON products
      USING bm25 (id, (description::pdb.simple))
      WITH (key_field='id')
      WHERE archived_at IS NULL
    SQL
  end

  it "renders concurrent create index SQL" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: Tokenizer.simple() }
      }
    end

    sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: true, concurrently: true)
    assert_sql_equal <<~SQL, sql
      CREATE INDEX CONCURRENTLY IF NOT EXISTS products_bm25_idx ON products
      USING bm25 (id, (description::pdb.simple))
      WITH (key_field='id')
    SQL
  end

  it "rejects mixing tokenizers with single tokenizer keys" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: {
          tokenizers: [Tokenizer.literal()],
          tokenizer: Tokenizer.simple()
        }
      }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "cannot mix"
  end

  it "rejects non-Tokenizer tokenizer config" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
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
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: Tokenizer.simple() },
        category: { tokenizer: Tokenizer.literal() },
        "metadata->>'title'" => { tokenizer: Tokenizer.simple(options: {alias: "metadata_title"}) }
      }
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
      self.fields = { id: {} }
    end

    assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
  end

  it "requires alias for ambiguous entries" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: {
          tokenizers: [
            Tokenizer.simple(),
            Tokenizer.literal()
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
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: {
          tokenizers: [
            Tokenizer.simple(options: {alias: "description_simple"}),
            Tokenizer.literal(options: {alias: "description_exact"})
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
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: Tokenizer.ngram(2, 5) }
      }
    end

    sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: false)
    assert_sql_equal <<~SQL, sql
      CREATE INDEX products_bm25_idx ON products
      USING bm25 (id, (description::pdb.ngram(2, 5)))
      WITH (key_field='id')
    SQL
  end

  it "rejects non-Tokenizer values in tokenizers arrays" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizers: [Tokenizer.literal(), :simple] }
      }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) { klass.compiled_definition }
    assert_includes error.message, "must be a Tokenizer"
  end

  it "renders custom tokenizer objects" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: { tokenizer: Tokenizer.new("pdb::xyz", nil, nil) },
        "metadata->>'title'" => { tokenizer: Tokenizer.new("pdb::abc", [12, "fafda"], nil) }
      }
    end

    sql = ActiveRecord::Base.connection.send(:build_create_sql, klass.compiled_definition, if_not_exists: false)
    assert_sql_equal <<~SQL, sql
      CREATE INDEX products_bm25_idx ON products
      USING bm25 (id, (description::pdb::xyz), ((metadata->>'title')::pdb::abc(12, 'fafda')))
      WITH (key_field='id')
    SQL
  end

  it "round-trips tokenizer args through schema ruby" do
    klass = Class.new(ParadeDB::Index) do
      self.table_name = :products
      self.key_field = :id
      self.fields = {
        id: {},
        description: {
          tokenizer: Tokenizer.ngram(2, 5, options: {prefix_only: true, alias: "description_ngram"})
        }
      }
    end

    conn = ActiveRecord::Base.connection
    compiled = klass.compiled_definition
    indexdef = conn.send(:build_create_sql, compiled, if_not_exists: false)
    ruby_stmt = conn.send(
      :bm25_index_to_ruby,
      {
        "indexdef" => indexdef,
        "table_name" => compiled.table_name.to_s,
        "index_name" => compiled.index_name.to_s
      }
    )

    recorder = Class.new do
      attr_reader :captured

      def add_bm25_index(table, fields:, key_field:, name:, index_options: nil, if_not_exists: false)
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

  it "parses nested parentheses in WITH clauses before trailing SQL" do
    conn = ActiveRecord::Base.connection
    indexdef = <<~SQL.squish
      CREATE INDEX products_bm25_idx ON public.products
      USING bm25 (id, description)
      WITH (key_field=id, target_segment_count=((17)))
      WHERE ((archived_at IS NULL))
    SQL

    with_sql, trailing_sql = conn.send(:extract_bm25_with_components, indexdef)

    assert_equal "key_field=id, target_segment_count=((17))", with_sql
    assert_equal "WHERE ((archived_at IS NULL))", trailing_sql
  end
end
