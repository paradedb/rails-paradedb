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
    body: { tokenizer: ParadeDB::Tokenizer.simple() },
    tag: {}
  }
end

RSpec.describe "KeyFieldRuntime" do
  before do
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
    conn.execute("CREATE EXTENSION IF NOT EXISTS pg_search CASCADE;")
    conn.remove_paradedb_index(:runtime_key_docs, name: :runtime_key_docs_search_idx, if_exists: true)
    conn.create_paradedb_index(RuntimeKeyDocIndex)
  end

  after do
    conn = ActiveRecord::Base.connection
    conn.remove_paradedb_index(:runtime_key_docs, name: :runtime_key_docs_search_idx, if_exists: true) rescue nil
    conn.drop_table(:runtime_key_docs, if_exists: true) rescue nil
  end

  it "with_score works with non-primary-key key_field" do
    sql = RuntimeKeyDoc.search(:body).match_all("wireless").with_score.order(search_score: :desc).limit(3).to_sql

    assert_query_sql <<~SQL, sql
      SELECT runtime_key_docs.*, pdb.score("runtime_key_docs"."external_id") AS search_score FROM runtime_key_docs
      WHERE ("runtime_key_docs"."body" &&& 'wireless')
      ORDER BY search_score DESC
      LIMIT 3
    SQL
  end

  it "more_like_this uses DSL key_field value" do
    sql = RuntimeKeyDoc.more_like_this(101, fields: [:body]).order(:external_id).to_sql

    assert_query_sql <<~SQL, sql
      SELECT runtime_key_docs.* FROM runtime_key_docs
      WHERE ("runtime_key_docs"."external_id" @@@ pdb.more_like_this(101, ARRAY['body']))
      ORDER BY "runtime_key_docs"."external_id" ASC
    SQL
  end

  it "with_facets without ParadeDB predicates works with non-primary-key key_field" do
    relation = RuntimeKeyDoc.where(tag: "audio")
                            .extending(ParadeDB::SearchMethods)
                            .with_facets(agg: { "value_count" => { "field" => "external_id" } })
                            .order(:external_id)
                            .limit(10)

    assert_query_sql <<~SQL, relation.to_sql
      SELECT runtime_key_docs.*, pdb.agg('{"value_count":{"field":"external_id"}}') OVER () AS _agg_facet FROM runtime_key_docs
      WHERE "runtime_key_docs"."tag" = 'audio' AND ("runtime_key_docs"."external_id" @@@ pdb.all())
      ORDER BY "runtime_key_docs"."external_id" ASC
      LIMIT 10
    SQL
  end
end
