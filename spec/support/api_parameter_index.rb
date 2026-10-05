# frozen_string_literal: true

class ApiParameterItem < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = "api_parameter_items"
end

RSpec.shared_context "API parameter index" do
  before(:context) do
    connection = ActiveRecord::Base.connection
    connection.execute("CREATE TABLE api_parameter_items (id int PRIMARY KEY, description text)")
    connection.execute("INSERT INTO api_parameter_items VALUES (1, 'red shoes'), (2, 'red boots'), (3, 'blue shoes')")
    connection.add_paradedb_index(:api_parameter_items, name: :api_parameter_idx, fields: {id: {}, description: {}}, index_options: {
      search_tokenizer: ParadeDB::Tokenizer.simple(options: {lowercase: true}), layer_sizes: "0", background_layer_sizes: "100MB, 1GB", mutable_segment_rows: 0
    })
  end

  after(:context) { ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS api_parameter_items") }

  let(:conjunction) { ParadeDB::SearchQuery.boolean(should: ["description:red", "description:shoes"], minimum_should_match: 2) }
  let(:query) { ParadeDB::SearchQuery.boolean(must: [ParadeDB::SearchQuery.disjunction_max([conjunction, "description:boots"], tie_breaker: 0.5)], must_not: ["description:blue"]) }
end
