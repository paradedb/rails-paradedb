# frozen_string_literal: true

require "spec_helper"
require "stringio"

class IndexMigrationBook < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :books
end

class IndexMigrationBookIndex < ParadeDB::Index
  self.table_name = :books
  self.key_field = :id
  self.index_options = { target_segment_count: 17 }
  self.fields = {
    id: {},
    title: {
      tokenizers: [
        { tokenizer: :literal },
        { tokenizer: :simple, alias: "title_simple", filters: [:lowercase] }
      ]
    },
    author: { tokenizer: :literal },
    metadata: { fast: true, expand_dots: false }
  }
end

class IndexMigrationBookByNameIndex < ParadeDB::Index
  self.table_name = :books
  self.key_field = :id
  self.index_name = :books_by_name_bm25_idx
  self.fields = {
    id: {},
    title: { tokenizer: :simple }
  }
end

RSpec.describe "IndexMigrationIntegrationTest" do
  before do
    skip "Integration test requires PostgreSQL" unless postgresql?

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")

    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :books, force: true do |t|
          t.text :title
          t.text :author
          t.jsonb :metadata, default: {}
        end
      end
    end

    conn.remove_bm25_index(:books, if_exists: true)
    conn.create_paradedb_index(IndexMigrationBookIndex)
  end

  after do
    next unless postgresql?

    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true) rescue nil
    conn.drop_table(:books, if_exists: true) rescue nil
  end

  it "creates bm25 index through create_paradedb_index" do
    sql = <<~SQL
      SELECT am.amname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_index i ON i.indexrelid = c.oid
      JOIN pg_am am ON am.oid = c.relam
      WHERE c.relname = 'books_bm25_idx' AND n.nspname = current_schema()
      LIMIT 1
    SQL

    am_name = ActiveRecord::Base.connection.select_value(sql)
    assert_equal "bm25", am_name
  end

  it "supports searching data after index creation" do
    IndexMigrationBook.create!(title: "Ruby on Rails guide", author: "DHH")
    IndexMigrationBook.create!(title: "Distributed systems", author: "Tanenbaum")

    ids = IndexMigrationBook.search(:title_simple).matching_all("rails").pluck(:id)
    assert_equal 1, ids.length
  end

  it "raises when multiple tokenizers for a field are missing aliases" do
    bad_index = Class.new(ParadeDB::Index) do
      self.table_name = :books
      self.key_field = :id
      self.fields = {
        id: {},
        title: {
          tokenizers: [
            { tokenizer: :literal },
            { tokenizer: :simple }
          ]
        }
      }
    end

    error = assert_raises(ParadeDB::InvalidIndexDefinition) do
      ActiveRecord::Base.connection.create_paradedb_index(bad_index)
    end
    assert_includes error.message, "alias"
  end

  it "supports create_paradedb_index with string class names" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)
    conn.remove_bm25_index(:books, name: :books_by_name_bm25_idx, if_exists: true)

    conn.create_paradedb_index("IndexMigrationBookByNameIndex", if_not_exists: true)

    assert index_exists?("books_by_name_bm25_idx")
  end

  it "create_paradedb_index supports where" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)
    conn.remove_bm25_index(:books, name: :books_filtered_bm25_idx, if_exists: true)

    index_klass = Class.new(ParadeDB::Index) do
      self.table_name = :books
      self.key_field = :id
      self.index_name = :books_filtered_bm25_idx
      self.where = "author IS NOT NULL"
      self.fields = {
        id: {},
        title: { tokenizer: :simple },
        author: {}
      }
    end

    conn.create_paradedb_index(index_klass)

    assert_sql_equal <<~SQL, indexdef_for("books_filtered_bm25_idx")
      CREATE INDEX books_filtered_bm25_idx ON public.books
      USING bm25 (id, ((title)::pdb.simple), author)
      WITH (key_field=id)
      WHERE (author IS NOT NULL)
    SQL
  end

  it "supports add and remove bm25 index helpers" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    conn.add_bm25_index(
      :books,
      fields: {
        id: {},
        title: { tokenizer: :simple }
      },
      key_field: :id,
      name: :books_custom_bm25_idx,
      if_not_exists: true
    )
    assert index_exists?("books_custom_bm25_idx")

    conn.remove_bm25_index(:books, name: :books_custom_bm25_idx, if_exists: true)
    assert_not index_exists?("books_custom_bm25_idx")
  end

  it "supports partial bm25 indexes with where clauses" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    conn.add_bm25_index(
      :books,
      fields: {
        id: {},
        title: { tokenizer: :simple }
      },
      key_field: :id,
      name: :books_partial_bm25_idx,
      where: "author IS NOT NULL",
      if_not_exists: true
    )

    assert index_exists?("books_partial_bm25_idx")
    assert_sql_equal <<~SQL, indexdef_for("books_partial_bm25_idx")
      CREATE INDEX books_partial_bm25_idx ON public.books
      USING bm25 (id, ((title)::pdb.simple))
      WITH (key_field=id)
      WHERE (author IS NOT NULL)
    SQL

    conn.remove_bm25_index(:books, name: :books_partial_bm25_idx, if_exists: true)
  end

  it "rolls back create_paradedb_index in change migrations" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)
    conn.remove_bm25_index(:books, name: :books_by_name_bm25_idx, if_exists: true)

    migration = build_change_migration do
      create_paradedb_index(IndexMigrationBookByNameIndex, if_not_exists: true)
    end

    run_migration(migration, :up, connection: conn)
    assert index_exists?("books_by_name_bm25_idx")

    run_migration(migration, :down, connection: conn)
    assert_not index_exists?("books_by_name_bm25_idx")
  end

  it "rolls back add_bm25_index in change migrations" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)
    conn.remove_bm25_index(:books, name: :books_custom_bm25_idx, if_exists: true)

    migration = build_change_migration do
      add_bm25_index(
        :books,
        fields: {
          id: {},
          title: { tokenizer: :simple }
        },
        key_field: :id,
        name: :books_custom_bm25_idx,
        if_not_exists: true
      )
    end

    run_migration(migration, :up, connection: conn)
    assert index_exists?("books_custom_bm25_idx")

    run_migration(migration, :down, connection: conn)
    assert_not index_exists?("books_custom_bm25_idx")
  end

  it "raises for remove_bm25_index in change migrations" do
    conn = ActiveRecord::Base.connection

    migration = build_change_migration do
      remove_bm25_index(:books, if_exists: true)
    end

    run_migration(migration, :up, connection: conn)
    assert_not index_exists?("books_bm25_idx")

    error = assert_raises(ActiveRecord::IrreversibleMigration) do
      run_migration(migration, :down, connection: conn)
    end
    assert_includes error.message, "remove_bm25_index"
  end

  it "supports replace_paradedb_index helper" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    v1 = Class.new(ParadeDB::Index) do
      self.table_name = :books
      self.key_field = :id
      self.fields = {
        id: {},
        title: { tokenizer: :simple }
      }
    end
    v2 = Class.new(ParadeDB::Index) do
      self.table_name = :books
      self.key_field = :id
      self.fields = {
        id: {},
        title: { tokenizer: :simple },
        author: { tokenizer: :literal }
      }
    end

    conn.create_paradedb_index(v1)
    before_indexdef = indexdef_for("books_bm25_idx")

    conn.replace_paradedb_index(v2)
    after_indexdef = indexdef_for("books_bm25_idx")

    refute_equal before_indexdef, after_indexdef
    assert_sql_equal <<~SQL, after_indexdef
      CREATE INDEX books_bm25_idx ON public.books
      USING bm25 (id, ((title)::pdb.simple), ((author)::pdb.literal))
      WITH (key_field=id)
    SQL
  end

  it "supports reindex_bm25 and guards concurrent reindex in a transaction" do
    conn = ActiveRecord::Base.connection

    conn.reindex_bm25(:books)

    error = assert_raises(ArgumentError) do
      conn.transaction do
        conn.reindex_bm25(:books, concurrently: true)
      end
    end
    assert_includes error.message, "cannot run inside a transaction"
  end

  it "makes create_paradedb_index idempotent with if_not_exists" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    conn.create_paradedb_index(IndexMigrationBookIndex, if_not_exists: true)
    conn.create_paradedb_index(IndexMigrationBookIndex, if_not_exists: true)

    assert_equal 1, bm25_index_count("books_bm25_idx")
  end

  it "dumps bm25 indexes from catalog into schema output" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)
    conn.add_bm25_index(
      :books,
      fields: {
        id: {},
        title: { tokenizer: :simple, alias: "title_simple" }
      },
      key_field: :id,
      index_options: { target_segment_count: 17 },
      if_not_exists: true
    )
    conn.instance_variable_set(:@paradedb_schema_index_references, [])

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    schema = stream.string

    add_stmt = schema.each_line.find do |line|
      line.include?("add_bm25_index :books") &&
        line.include?("title_simple") &&
        line.include?("target_segment_count")
    end

    assert_equal <<~RUBY.strip, add_stmt.to_s.strip
      add_bm25_index :books, fields: { id: {}, title: { tokenizer: :simple, alias: "title_simple" } }, key_field: :id, name: "books_bm25_idx", index_options: { :target_segment_count => 17 }
    RUBY
    expect(schema).not_to match(/add_index.*books_bm25_idx/)
    expect(schema).not_to match(/t\.index.*books_bm25_idx/)
  end

  it "creates tokenized expression indexes and persists expression in catalog" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    expression_index = Class.new(ParadeDB::Index) do
      self.table_name = :books
      self.key_field = :id
      self.fields = {
        id: {},
        "(metadata->>'title')::text": {
          tokenizer: :simple,
          alias: "metadata_title"
        }
      }
    end

    conn.create_paradedb_index(expression_index)
    indexdef = indexdef_for("books_bm25_idx")

    assert_sql_equal <<~SQL, indexdef
      CREATE INDEX books_bm25_idx ON public.books
      USING bm25 (id, (((metadata ->> 'title'::text))::pdb.simple('alias=metadata_title')))
      WITH (key_field=id)
    SQL
  end

  it "allows aliased computed numeric expressions without requiring a tokenizer" do
    conn = ActiveRecord::Base.connection

    conn.execute("DROP INDEX IF EXISTS search_idx;")
    conn.drop_table(:mock_items, if_exists: true)
    conn.create_table(:mock_items) do |t|
      t.text :description
      t.integer :rating
    end

    expect do
      conn.add_bm25_index(
        :mock_items,
        fields: {
          id: {},
          description: {},
          "(rating + 1)" => { alias: "rating" }
        },
        key_field: :id,
        name: :search_idx
      )
    end.not_to raise_error

    assert_sql_equal <<~SQL, indexdef_for("search_idx")
      CREATE INDEX search_idx ON public.mock_items
      USING bm25 (id, description, (((rating + 1))::pdb.alias('rating')))
      WITH (key_field=id)
    SQL
    assert index_exists?("search_idx")
  ensure
    conn.execute("DROP INDEX IF EXISTS search_idx;") rescue nil
    conn.drop_table(:mock_items, if_exists: true) rescue nil
  end

  it "round-trips schema dump/load for structured multi-tokenizer fields" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    conn.add_bm25_index(
      :books,
      fields: {
        id: {},
        title: {
          tokenizers: [
            { tokenizer: :literal },
            { tokenizer: :simple, alias: "title_simple" }
          ]
        }
      },
      key_field: :id,
      index_options: { target_segment_count: 17 },
      if_not_exists: true
    )

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    schema = stream.string
    add_stmt = schema.each_line.find do |line|
      line.include?("add_bm25_index :books") &&
        line.include?("title_simple") &&
        line.include?("target_segment_count")
    end

    assert_equal <<~RUBY.strip, add_stmt.to_s.strip
      add_bm25_index :books, fields: { id: {}, title: { tokenizers: [{ tokenizer: :literal }, { tokenizer: :simple, alias: "title_simple" }] } }, key_field: :id, name: "books_bm25_idx", index_options: { :target_segment_count => 17 }
    RUBY

    conn.remove_bm25_index(:books, if_exists: true)
    expect { conn.instance_eval(add_stmt.strip) }.not_to raise_error
    assert index_exists?("books_bm25_idx")
  end

  it "round-trips schema dump/load for structured expression fields with casts" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    conn.add_bm25_index(
      :books,
      fields: {
        id: {},
        "(metadata->>'title')::text": {
          tokenizer: :simple,
          alias: "metadata_title_text",
          filters: [:lowercase]
        }
      },
      key_field: :id,
      if_not_exists: true
    )

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    schema = stream.string
    add_stmt = schema.each_line.find do |line|
      line.include?("add_bm25_index :books") && line.include?("metadata_title_text")
    end

    assert_equal <<~RUBY.strip, add_stmt.to_s.strip
      add_bm25_index :books, fields: { id: {}, "metadata ->> 'title'::text" => { tokenizer: :simple, alias: "metadata_title_text", named_args: { :lowercase => true } } }, key_field: :id, name: "books_bm25_idx"
    RUBY

    conn.remove_bm25_index(:books, if_exists: true)
    expect { conn.instance_eval(add_stmt.strip) }.not_to raise_error
    assert index_exists?("books_bm25_idx")
  end

  it "round-trips schema dump/load for partial bm25 indexes" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    conn.add_bm25_index(
      :books,
      fields: {
        id: {},
        title: { tokenizer: :simple, alias: "title_simple" }
      },
      key_field: :id,
      where: "author IS NOT NULL",
      if_not_exists: true
    )

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    schema = stream.string
    add_stmt = schema.each_line.find do |line|
      line.include?("add_bm25_index :books") &&
        line.include?("title_simple") &&
        line.include?("where:")
    end

    assert_equal <<~RUBY.strip, add_stmt.to_s.strip
      add_bm25_index :books, fields: { id: {}, title: { tokenizer: :simple, alias: "title_simple" } }, key_field: :id, name: "books_bm25_idx", where: "author IS NOT NULL"
    RUBY

    conn.remove_bm25_index(:books, if_exists: true)
    expect { conn.instance_eval(add_stmt.strip) }.not_to raise_error
    assert_sql_equal <<~SQL, indexdef_for("books_bm25_idx")
      CREATE INDEX books_bm25_idx ON public.books
      USING bm25 (id, ((title)::pdb.simple('alias=title_simple')))
      WITH (key_field=id)
      WHERE (author IS NOT NULL)
    SQL
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end

  def index_exists?(index_name)
    bm25_index_count(index_name).positive?
  end

  def bm25_index_count(index_name)
    sql = <<~SQL
      SELECT COUNT(*)
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relname = #{ActiveRecord::Base.connection.quote(index_name)}
        AND n.nspname = current_schema()
    SQL
    ActiveRecord::Base.connection.select_value(sql).to_i
  end

  def indexdef_for(index_name)
    sql = <<~SQL
      SELECT pg_get_indexdef(c.oid)
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relname = #{ActiveRecord::Base.connection.quote(index_name)}
        AND n.nspname = current_schema()
      LIMIT 1
    SQL
    ActiveRecord::Base.connection.select_value(sql).to_s
  end

  def build_change_migration(&block)
    Class.new(ActiveRecord::Migration[ActiveRecord::Migration.current_version]) do
      define_method(:change, &block)
    end
  end

  def run_migration(migration_class, direction, connection:)
    migration = migration_class.new
    migration.suppress_messages do
      migration.exec_migration(connection, direction)
    end
  end
end
