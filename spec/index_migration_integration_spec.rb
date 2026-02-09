# frozen_string_literal: true

require "spec_helper"

class Book < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :books
  self.has_paradedb_index = true
end

class BookIndex < ParadeDB::Index
  self.table_name = :books
  self.key_field = :id
  self.fields = [
    :id,
    { title: :simple },
    { author: :literal }
  ]
end

class IndexMigrationIntegrationTest < Minitest::Test
  def setup
    skip "Integration test requires PostgreSQL" unless postgresql?

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")

    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :books, force: true do |t|
          t.text :title
          t.text :author
        end
      end
    end

    conn.remove_bm25_index(:books, if_exists: true)
    conn.create_paradedb_index(BookIndex)
  end

  def test_create_paradedb_index_creates_bm25_index
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

  def test_book_search_works_on_new_model_and_table
    Book.create!(title: "Ruby on Rails guide", author: "DHH")
    Book.create!(title: "Distributed systems", author: "Tanenbaum")

    ids = Book.search(:title).matching_all("rails").pluck(:id)
    assert_equal 1, ids.length
  end

  def test_create_paradedb_index_raises_for_ambiguous_dsl
    bad_index = Class.new(ParadeDB::Index) do
      self.table_name = :books
      self.key_field = :id
      self.fields = [
        { title: :simple },
        { title: :literal }
      ]
    end

    assert_raises(ParadeDB::InvalidIndexDefinition) do
      ActiveRecord::Base.connection.create_paradedb_index(bad_index)
    end
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end
end
