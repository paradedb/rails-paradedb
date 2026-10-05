# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ParadeDB 0.26.0 features" do
  it "creates partitioned vector indexes and preserves options in schema dumps" do
    connection = ActiveRecord::Base.connection
    connection.execute("CREATE TABLE pg26_items (id int, rating int, description text, embedding vector(64))")
    begin
      connection.execute("INSERT INTO pg26_items SELECT i, i % 3, 'partitioned shoes', ARRAY(SELECT sin(i*j)::real FROM generate_series(1,64) j)::vector FROM generate_series(1, 2048) i")
      connection.add_paradedb_index(:pg26_items, name: :pg26_idx, fields: {id: {}, rating: {}, description: {tokenizers: [ParadeDB::Tokenizer.simple(options: {pnorms: true}), ParadeDB::Tokenizer.jieba(options: {alias: "description_jieba", search_mode: false}), ParadeDB::Tokenizer.chinese_compatible(options: {alias: "description_chinese", chinese_convert: "t2s"})]}, embedding: {metric: :l2}}, index_options: {partition_by: "rating,id", target_segment_count: 8, vector_fields: {embedding: {quantization: false}}})
      options = connection.select_value("SELECT reloptions FROM pg_class WHERE oid = 'pg26_idx'::regclass")
      expect(options).to include("partition_by=rating,id", "target_segment_count=8")
      dump = StringIO.new
      ActiveRecord::SchemaDumper.dump(connection.pool, dump)
      expect(dump.string).to include(':partition_by => "rating,id"', ':vector_fields =>')
      expect(ParadeDB::Diagnostics.vector_config("pg26_idx", "embedding").first["quantized"]).to eq(false)
      expect(ParadeDB::Diagnostics.vector_info("pg26_idx", "embedding")).not_to be_empty
      connection.execute("ALTER INDEX pg26_idx SET (target_segment_count = 1, max_leaf_size = 16, vector_fields = '{\"embedding\":{\"quantization\":true}}')")
      connection.execute("REINDEX INDEX pg26_idx")
      expect(ParadeDB::Diagnostics.vector_config("pg26_idx", "embedding").first["quantized"]).to eq(true)
      expect(ParadeDB::Diagnostics.vector_estimator_info("pg26_idx", "embedding")).to be_an(Array)
      expect(ParadeDB::Diagnostics.vector_estimator_info("pg26_idx", "embedding", queries: [Array.new(64, 0.1)])).to be_an(Array)
      expect(connection.select_value("SELECT COUNT(*) FROM pg26_items WHERE description @@@ 'shoes' AND rating = 1")).to eq(683)
      model = Class.new(ActiveRecord::Base) do
        include ParadeDB::Model
        self.table_name = "pg26_items"
      end
      %w[transaction raw threshold].each do |visibility|
        result = model.search(:id).match_all.facets_agg(visibility: visibility, count: ParadeDB::Aggregations.value_count(:id))
        expect(result["count"]["value"]).to eq(2048)
      end
    ensure
      connection.execute("DROP TABLE pg26_items")
    end
  end
end
