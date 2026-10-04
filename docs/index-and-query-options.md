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

## Search tokenizer and index tuning

`search_tokenizer` sets the default search-time tokenizer. `layer_sizes` and `background_layer_sizes` are comma-separated PostgreSQL size strings, such as `"100MB, 1GB"`. Use `"0"` to disable the corresponding merge mode. `mutable_segment_rows` accepts an integer from 0 through 10000; 0 disables mutable segments. Omitted options keep the server defaults.

```ruby
# Add these to add_paradedb_index's index_options:
# search_tokenizer: ParadeDB::Tokenizer.simple(options: {lowercase: false}),
# layer_sizes: "0", background_layer_sizes: "100MB, 1GB", mutable_segment_rows: 1000
query = ParadeDB::SearchQuery.boolean(
  should: ["description:running", "description:shoes"],
  minimum_should_match: 2,
  must_not: ["category:discontinued"]
)
query = ParadeDB::SearchQuery.disjunction_max([query, "description:boots"], tie_breaker: 0.5)
items = Item.search(:id).search_query(query)
result = ParadeDB::Diagnostics.aggregate(
  "items_search_idx", query,
  {count: {value_count: {field: "id"}}},
  memory_limit: 10000000, bucket_limit: 100, visibility: "transaction"
)
```

`with_snippet` and `with_snippet_positions` accept `limit` and `offset`. Snippet formatting options can be supplied independently, including `max_chars` without tags, and compile to named SQL arguments. Migration helpers and schema dumps preserve all the index options above.

Query strings use ParadeDB's query syntax and may include field qualifiers. Boolean clauses and disjunction-max inputs can be nested. `minimum_should_match` is a non-negative integer. `tie_breaker` ranges from 0 to 1: 0 uses the best matching subquery's score, while larger values also include contributions from other matching subqueries. Apply composed queries to the index's first key column, and refer to actual index field names or aliases in field qualifiers.

## Highlight pagination and direct aggregate limits

ParadeDB 0.26.0 accepts `limit` and `offset` on `snippet`, but deprecates them in favor of `snippets`. Prefer the existing multiple-snippet helper for new paginated highlighting. `snippet_positions` pagination is also exposed. Formatting and pagination options are optional; omitting earlier options retains the server defaults.

The direct aggregate helper calls `paradedb.aggregate`, independently of the existing `pdb.agg` expression. It accepts positive integer memory and bucket limits. The memory limit is in bytes and defaults to 500000000; an omitted bucket limit uses the server setting. Visibility accepts `transaction`, `raw`, or `threshold`. Supply either visibility or the compatibility `solve_mvcc` boolean, never both. Database errors, including exceeding a resource limit, propagate to the caller.
