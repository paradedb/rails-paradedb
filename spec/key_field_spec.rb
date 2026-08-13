# frozen_string_literal: true

require "spec_helper"

class RuntimeKeyMockItemIndex < ParadeDB::Index
  self.table_name = :mock_items
  self.key_field = :id
  self.fields = {
    id: {},
    description: { tokenizer: ParadeDB::Tokenizer.simple() },
    category: {}
  }
end

class RuntimeKeyMockItem < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = :mock_items
  self.primary_key = :rating

  paradedb_index RuntimeKeyMockItemIndex
end

RSpec.describe "KeyFieldRuntime" do
  before do
    remove_test_indexes
    ActiveRecord::Base.connection.create_paradedb_index(RuntimeKeyMockItemIndex)
  end

  after { remove_test_indexes }

  it "with_score uses the DSL key field instead of the model primary key" do
    sql = RuntimeKeyMockItem.search(:description).match_all("wireless").with_score.order(search_score: :desc).limit(3).to_sql

    assert_query_sql <<~SQL, sql
      SELECT mock_items.*, pdb.score("mock_items"."id") AS search_score FROM mock_items
      WHERE ("mock_items"."description" &&& 'wireless')
      ORDER BY search_score DESC
      LIMIT 3
    SQL
  end

  it "more_like_this uses the DSL key field" do
    sql = RuntimeKeyMockItem.more_like_this(1, fields: [:description]).order(:id).to_sql

    assert_query_sql <<~SQL, sql
      SELECT mock_items.* FROM mock_items
      WHERE ("mock_items"."id" @@@ pdb.more_like_this(1, ARRAY['description']))
      ORDER BY "mock_items"."id" ASC
    SQL
  end

  it "with_facets uses the DSL key field for match all" do
    relation = RuntimeKeyMockItem.where(category: "Electronics")
                                 .extending(ParadeDB::SearchMethods)
                                 .with_facets(agg: { "value_count" => { "field" => "id" } })
                                 .order(:id)
                                 .limit(10)

    assert_query_sql <<~SQL, relation.to_sql
      SELECT mock_items.*, pdb.agg('{"value_count":{"field":"id"}}') OVER () AS _agg_facet FROM mock_items
      WHERE "mock_items"."category" = 'Electronics' AND ("mock_items"."id" @@@ pdb.all())
      ORDER BY "mock_items"."id" ASC
      LIMIT 10
    SQL
  end
end
