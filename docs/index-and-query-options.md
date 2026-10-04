# Index and query options

## Partitioning and vector configuration

[ParadeDB 0.26.0](https://www.paradedb.com/docs/project/changelog/0.26.0) adds segment partitioning and quantized vector storage. Partition keys are comma-separated **index field names**, including tokenizer aliases when applicable. Each key must be single-valued and columnar. Numeric columns work directly; text keys need a columnar tokenizer such as `literal`. PostgreSQL validates the field types when creating the index.

```ruby
add_paradedb_index :items,
  name: :items_search_idx,
  fields: {id: {}, tenant_id: {}, description: {}, embedding: {metric: :cosine}},
  index_options: {
    partition_by: "tenant_id",
    target_segment_count: 8,
    vector_fields: {embedding: {quantization: false}}
  }

Item.search(:id).match_all.facets_agg(
  visibility: :threshold,
  total: ParadeDB::Aggregations.value_count(:id)
)
ParadeDB::Diagnostics.vector_config("items_search_idx", "embedding")
```

The migration DSL and schema dumper preserve these index options. `visibility:` is also accepted by `facets`, `with_facets`, `with_agg`, and `aggregate_by`.

`target_segment_count` is a positive integer. Omit an option to retain the server default. Quantization can be disabled per vector field or configured with `{"quantization": {"layers": [1, 4]}}`. Quantization changes take effect at `CREATE INDEX` or `REINDEX`, so changing a reloption alone does not rebuild stored vectors.

The experimental stacked IVF router is available through `vector_router: "ivf"`. Its default remains `graph`.

## Aggregate visibility

- `transaction` applies transaction visibility checks and is the default.
- `raw` skips visibility checks and may include deleted or otherwise invisible rows.
- `threshold` applies checks only when the estimated match count is below `paradedb.visibility_threshold`.

The existing `exact` option remains supported. When using a named visibility option, omit the legacy boolean option.

Combining `FILTER` with a window aggregate is subject to server feature flags in 0.26.0.

## Vector diagnostics

Use `vector_info`, `vector_config`, and `vector_estimator_info` to inspect vector storage, build configuration, and estimator error. Each accepts an index name and vector field name. The estimator helper also accepts an optional collection of query vectors. Names and queries are safely quoted or passed as SQL parameters.

Estimator diagnostics require at least one visible quantized IVF segment. An empty index or an index with only flat or unquantized segments returns a PostgreSQL error. Flat segments return null for IVF and quantization metadata where it does not apply. These are diagnostic operations, especially the estimator, and should not run on every application request.

## Tokenizer options

The existing tokenizer option dictionaries support the new options:

```ruby
ParadeDB::Tokenizer.simple(options: {pnorms: true})
ParadeDB::Tokenizer.jieba(options: {search_mode: false})
ParadeDB::Tokenizer.chinese_compatible(options: {chinese_convert: "t2s"})
```

## Planner improvements and runtime settings

DISTINCT, aggregates over joins, date grouping, and range ordering use normal ORM query expressions. ParadeDB chooses eligible pushdowns automatically. Runtime settings, including spill behavior and vector scan limits, can be configured through the framework's normal SQL connection API and require no separate query helpers.
