# frozen_string_literal: true

require "spec_helper"

class ApiParameterItem < ActiveRecord::Base
  include ParadeDB::Model
  self.table_name = "api_parameter_items"
end

RSpec.describe "API parameter coverage" do
  before(:context) do
    connection = ActiveRecord::Base.connection
    connection.execute("CREATE TABLE api_parameter_items (id int PRIMARY KEY, description text)")
    connection.execute("INSERT INTO api_parameter_items VALUES (1, 'red shoes'), (2, 'red boots'), (3, 'blue shoes')")
    connection.add_paradedb_index(:api_parameter_items, name: :api_parameter_idx, fields: {id: {}, description: {}}, index_options: {
      search_tokenizer: ParadeDB::Tokenizer.simple(options: {lowercase: true}), layer_sizes: "0", background_layer_sizes: "100MB, 1GB", mutable_segment_rows: 0
    })
  end

  after(:context) { ActiveRecord::Base.connection.execute("DROP TABLE api_parameter_items") }

  it "executes nested Boolean and disjunction-max queries and direct aggregates" do
    conjunction = ParadeDB::SearchQuery.boolean(should: ["description:red", "description:shoes"], minimum_should_match: 2)
    expect(ApiParameterItem.search(:id).search_query(conjunction).pluck(:id)).to eq([1])
    query = ParadeDB::SearchQuery.boolean(must: [ParadeDB::SearchQuery.disjunction_max([conjunction, "description:boots"], tie_breaker: 0.5)], must_not: ["description:blue"])
    expect(ApiParameterItem.search(:id).search_query(query).order(:id).pluck(:id)).to eq([1, 2])
    result = ParadeDB::Diagnostics.aggregate("api_parameter_idx", query, {count: {value_count: {field: "id"}}}, memory_limit: 10000000, bucket_limit: 100, visibility: "transaction")
    expect(result["count"]["value"]).to eq(2)
    expect { ParadeDB::Diagnostics.aggregate("api_parameter_idx", "description:red", {ids: {terms: {field: "id", size: 10}}}, memory_limit: 10000000, bucket_limit: 1) }.to raise_error(ActiveRecord::StatementInvalid, /bucket limit was exceeded/)
    expect(ApiParameterItem.search(:id).search_query('description:"O\'Reilly"').count).to eq(0)
  end

  it "supports sparse snippet options and pagination" do
    relation = ApiParameterItem.search(:description).match_any("shoes")
    expect(relation.with_snippet(:description, max_chars: 20).to_a.map(&:description_snippet)).to all(include("<b>"))
    expect(relation.with_snippet(:description, end_tag: "</mark>").to_a.map(&:description_snippet)).to all(include("</mark>"))
    rows = relation.with_snippet(:description, limit: 1, offset: 0).with_snippet_positions(:description, limit: 1, offset: 1).order(:id).to_a
    expect(rows.length).to eq(2)
    native = ActiveRecord::Base.connection.select_rows("SELECT id, pdb.snippet_positions(description, \"limit\" => 1, \"offset\" => 1) FROM api_parameter_items WHERE description ||| 'shoes' ORDER BY id")
    expect(rows.map { |row| [row.id, row.description_snippet_positions] }).to eq(native)
  end

  it "preserves index tuning options through schema dumps" do
    connection = ActiveRecord::Base.connection
    options = connection.select_value("SELECT reloptions FROM pg_class WHERE oid = 'api_parameter_idx'::regclass")
    expect(options).to include("layer_sizes=0", "background_layer_sizes=100MB, 1GB", "mutable_segment_rows=0", "search_tokenizer=simple(lowercase=true)")
    dump = StringIO.new
    ActiveRecord::SchemaDumper.dump(connection.pool, dump)
    expect(dump.string).to include(':layer_sizes => "0"', ':background_layer_sizes => "100MB, 1GB"', ':mutable_segment_rows => 0', ':search_tokenizer => "simple(lowercase=true)"')
  end

  it "rejects invalid query and aggregate options" do
    expect { ParadeDB::SearchQuery.boolean(minimum_should_match: -1) }.to raise_error(ArgumentError, /minimum_should_match/)
    expect { ParadeDB::SearchQuery.disjunction_max(["description:shoes"], tie_breaker: Float::NAN) }.to raise_error(ArgumentError, /tie_breaker/)
    expect { ParadeDB::SearchQuery.disjunction_max([]) }.to raise_error(ArgumentError, /must not be empty/)
    expect { ParadeDB::Diagnostics.aggregate("idx", "*", {}, solve_mvcc: true, visibility: "raw") }.to raise_error(ArgumentError, /not both/)
  end
end
