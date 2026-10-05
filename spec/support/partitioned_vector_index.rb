# frozen_string_literal: true

RSpec.shared_context "partitioned vector index" do
  before(:context) do
    connection = ActiveRecord::Base.connection
    connection.execute("CREATE TABLE pg26_items (id int, rating int, description text, embedding vector(64))")
    connection.execute("INSERT INTO pg26_items SELECT i, i % 3, 'partitioned shoes', ARRAY(SELECT sin(i*j)::real FROM generate_series(1,64) j)::vector FROM generate_series(1, 2048) i")
    connection.add_paradedb_index(:pg26_items, name: :pg26_idx, fields: {id: {}, rating: {}, description: {tokenizers: [ParadeDB::Tokenizer.simple(options: {pnorms: true}), ParadeDB::Tokenizer.jieba(options: {alias: "description_jieba", search_mode: false}), ParadeDB::Tokenizer.chinese_compatible(options: {alias: "description_chinese", chinese_convert: "t2s"})]}, embedding: {metric: :l2}}, index_options: {partition_by: "rating,id", target_segment_count: 8, vector_fields: {embedding: {quantization: false}}})
  end

  after(:context) { ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS pg26_items") }
end
