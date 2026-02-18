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
  self.fields = [
    :id,
    { title: :simple },
    { author: :literal }
  ]
end

class IndexMigrationBookByNameIndex < ParadeDB::Index
  self.table_name = :books
  self.key_field = :id
  self.index_name = :books_by_name_bm25_idx
  self.fields = [
    :id,
    :title
  ]
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

    ids = IndexMigrationBook.search(:title).matching_all("rails").pluck(:id)
    assert_equal 1, ids.length
  end

  it "raises for ambiguous DSL definitions" do
    bad_index = Class.new(ParadeDB::Index) do
      self.table_name = :books
      self.key_field = :id
      self.fields = [
        :id,
        { title: :simple },
        { title: :literal }
      ]
    end

    assert_raises(ParadeDB::InvalidIndexDefinition) do
      ActiveRecord::Base.connection.create_paradedb_index(bad_index)
    end
  end

  it "supports create_paradedb_index with string class names" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)
    conn.remove_bm25_index(:books, name: :books_by_name_bm25_idx, if_exists: true)

    conn.create_paradedb_index("IndexMigrationBookByNameIndex", if_not_exists: true)

    assert index_exists?("books_by_name_bm25_idx")
  end

  it "supports add and remove bm25 index helpers" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    conn.add_bm25_index(
      :books,
      fields: [:id, :title],
      key_field: :id,
      name: :books_custom_bm25_idx,
      if_not_exists: true
    )
    assert index_exists?("books_custom_bm25_idx")

    conn.remove_bm25_index(:books, name: :books_custom_bm25_idx, if_exists: true)
    assert_not index_exists?("books_custom_bm25_idx")
  end

  it "supports replace_paradedb_index helper" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    v1 = Class.new(ParadeDB::Index) do
      self.table_name = :books
      self.key_field = :id
      self.fields = [:id, :title]
    end
    v2 = Class.new(ParadeDB::Index) do
      self.table_name = :books
      self.key_field = :id
      self.fields = [:id, :title, :author]
    end

    conn.create_paradedb_index(v1)
    before_indexdef = indexdef_for("books_bm25_idx")

    conn.replace_paradedb_index(v2)
    after_indexdef = indexdef_for("books_bm25_idx")

    refute_equal before_indexdef, after_indexdef
    assert_includes after_indexdef, "author"
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
    conn.add_bm25_index(:books, fields: [:id, :title], key_field: :id, if_not_exists: true)
    conn.instance_variable_set(:@paradedb_schema_index_references, [])

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    schema = stream.string

    assert_includes schema, "add_bm25_index"
    assert_includes schema, ":books"
    expect(schema).not_to match(/add_index.*books_bm25_idx/)
    expect(schema).not_to match(/t\.index.*books_bm25_idx/)
  end

  it "creates tokenized expression indexes and persists expression in catalog" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    expression_index = Class.new(ParadeDB::Index) do
      self.table_name = :books
      self.key_field = :id
      self.fields = [
        :id,
        { "metadata->>'title'" => { simple: { alias: "metadata_title" } } }
      ]
    end

    conn.create_paradedb_index(expression_index)
    indexdef = indexdef_for("books_bm25_idx")

    assert_includes indexdef, "metadata"
    assert_includes indexdef, "pdb.simple"
  end

  it "round-trips schema dump/load for tokenized fields with named tokenizer options" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    conn.add_bm25_index(
      :books,
      fields: [
        :id,
        { title: { simple: { alias: "title_simple" } } }
      ],
      key_field: :id,
      if_not_exists: true
    )

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    schema = stream.string
    add_stmt = schema.each_line.find do |line|
      line.include?("add_bm25_index :books") && line.include?("title_simple")
    end

    refute_nil add_stmt

    conn.remove_bm25_index(:books, if_exists: true)
    expect { conn.instance_eval(add_stmt.strip) }.not_to raise_error
    assert index_exists?("books_bm25_idx")
  end

  it "round-trips schema dump/load for tokenized expression fields with casts" do
    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:books, if_exists: true)

    conn.add_bm25_index(
      :books,
      fields: [
        :id,
        { "(metadata->>'title')::text" => { simple: { alias: "metadata_title_text" } } }
      ],
      key_field: :id,
      if_not_exists: true
    )

    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
    schema = stream.string
    add_stmt = schema.each_line.find do |line|
      line.include?("add_bm25_index :books") && line.include?("metadata_title_text")
    end

    refute_nil add_stmt
    assert_includes add_stmt, "metadata"
    assert_includes add_stmt, "title"
    assert_includes add_stmt, "::text"

    conn.remove_bm25_index(:books, if_exists: true)
    expect { conn.instance_eval(add_stmt.strip) }.not_to raise_error
    assert index_exists?("books_bm25_idx")
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
end
