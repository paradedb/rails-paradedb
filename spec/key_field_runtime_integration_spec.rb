# frozen_string_literal: true

require "spec_helper"

class RuntimeKeyDoc < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :runtime_key_docs
end

class RuntimeKeyDocIndex < ParadeDB::Index
  self.table_name = :runtime_key_docs
  self.key_field = :external_id
  self.fields = [
    :external_id,
    { body: :simple },
    :tag
  ]
end

class KeyFieldRuntimeIntegrationTest < Minitest::Test
  def setup
    skip "Integration tests require PostgreSQL" unless postgresql?

    ensure_schema!
    ensure_paradedb_setup!
    seed_docs!
  end

  def teardown
    return unless postgresql?

    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:runtime_key_docs, name: :runtime_key_docs_bm25_idx, if_exists: true) rescue nil
    conn.drop_table(:runtime_key_docs, if_exists: true) rescue nil
  end

  def test_with_score_works_with_non_primary_key_field
    rows = RuntimeKeyDoc.search(:body)
                        .matching_all("wireless")
                        .with_score
                        .order(search_score: :desc)
                        .limit(3)
                        .to_a

    refute_empty rows
    rows.each { |row| assert_operator row.search_score.to_f, :>=, 0.0 }
  end

  def test_more_like_this_uses_dsl_key_field_value
    ids = RuntimeKeyDoc.more_like_this(101, fields: [:body]).order(:external_id).pluck(:external_id)

    assert_includes ids, 102
  end

  def test_with_facets_without_paradedb_predicate_works_with_non_primary_key_field
    relation = RuntimeKeyDoc.where(tag: "audio")
                            .extending(ParadeDB::SearchMethods)
                            .with_facets(agg: { "value_count" => { "field" => "external_id" } })
                            .order(:external_id)
                            .limit(10)

    rows = relation.to_a
    refute_empty rows

    facets = relation.facets
    assert_kind_of Hash, facets
    assert_includes facets, "agg"
  end

  private

  def postgresql?
    ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
  end

  def ensure_schema!
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :runtime_key_docs, force: true do |t|
          t.integer :external_id, null: false
          t.text :body
          t.text :tag
        end
      end
    end
  end

  def ensure_paradedb_setup!
    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.remove_bm25_index(:runtime_key_docs, name: :runtime_key_docs_bm25_idx, if_exists: true)
    conn.create_paradedb_index(RuntimeKeyDocIndex)
  end

  def seed_docs!
    RuntimeKeyDoc.connection.execute("TRUNCATE TABLE runtime_key_docs RESTART IDENTITY;")

    RuntimeKeyDoc.create!(external_id: 101, body: "wireless bluetooth earbuds", tag: "audio")
    RuntimeKeyDoc.create!(external_id: 102, body: "wireless noise cancelling headphones", tag: "audio")
    RuntimeKeyDoc.create!(external_id: 103, body: "running shoes lightweight", tag: "footwear")
  end
end
