# frozen_string_literal: true

require "spec_helper"

class RuntimeKeyDoc < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :runtime_key_docs
end

class RuntimeKeyDocIndex < ParadeDB::Index
  self.table_name = :runtime_key_docs
  self.key_field = :external_id
  self.fields = {
    external_id: {},
    body: { tokenizer: Tokenizer.simple() },
    tag: {}
  }
end

RSpec.describe "KeyFieldRuntimeIntegrationTest" do
  before do
    skip "Integration tests require PostgreSQL" unless postgresql?

    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :runtime_key_docs, force: true do |t|
          t.integer :external_id, null: false
          t.text :body
          t.text :tag
        end
      end
    end

    conn = ActiveRecord::Base.connection
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search;")
    conn.remove_bm25_index(:runtime_key_docs, name: :runtime_key_docs_bm25_idx, if_exists: true)
    conn.create_paradedb_index(RuntimeKeyDocIndex)

    RuntimeKeyDoc.connection.execute("TRUNCATE TABLE runtime_key_docs RESTART IDENTITY;")
    RuntimeKeyDoc.create!(external_id: 101, body: "wireless bluetooth earbuds", tag: "audio")
    RuntimeKeyDoc.create!(external_id: 102, body: "wireless noise cancelling headphones", tag: "audio")
    RuntimeKeyDoc.create!(external_id: 103, body: "running shoes lightweight", tag: "footwear")
  end

  after do
    next unless postgresql?

    conn = ActiveRecord::Base.connection
    conn.remove_bm25_index(:runtime_key_docs, name: :runtime_key_docs_bm25_idx, if_exists: true) rescue nil
    conn.drop_table(:runtime_key_docs, if_exists: true) rescue nil
  end

  it "with_score works with non-primary-key key_field" do
    rows = RuntimeKeyDoc.search(:body)
                        .matching_all("wireless")
                        .with_score
                        .order(search_score: :desc)
                        .limit(3)
                        .to_a

    refute_empty rows
    rows.each { |row| assert_operator row.search_score.to_f, :>=, 0.0 }
  end

  it "more_like_this uses DSL key_field value" do
    ids = RuntimeKeyDoc.more_like_this(101, fields: [:body]).order(:external_id).pluck(:external_id)
    assert_includes ids, 102
  end

  it "with_facets without ParadeDB predicates works with non-primary-key key_field" do
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
end
