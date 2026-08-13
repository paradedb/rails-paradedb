# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **BREAKING**: Search modifiers are now composable functions: `ParadeDB.boost`, `ParadeDB.constant`, `ParadeDB.fuzzy`, `ParadeDB.slop`, and `ParadeDB.tokenize`. Pass the wrapped value to search methods instead of using modifier keyword arguments.

## [0.11.0] - 2026-08-04

### Added

- Vector index build options `centroid_ratio`, `training_samples_per_centroid`, and `cluster_replication` in `ParadeDB::Index` `index_options` and `add_paradedb_index` (pg_search 0.25.0+). They are emitted in the `WITH (...)` clause and round-tripped through the schema dumper.

## [0.10.0] - 2026-08-04

### Added

- Native pgvector `vector(n)` column support: ActiveRecord attribute type, `t.vector` / `add_column :table, :col, :vector, limit: n` migration DSL, and `schema.rb` dumping — no `neighbor` gem required.
- Vector fields in ParadeDB indexes via `embedding: { metric: :l2 | :cosine | :ip }` in `ParadeDB::Index` fields and `add_paradedb_index`, emitted as `vector_l2_ops` / `vector_cosine_ops` / `vector_ip_ops` opclasses and round-tripped through the schema dumper.
- `Model.nearest(column, vector, metric: nil)` for Top-K vector search. Orders by the pgvector distance operator (`<->`, `<=>`, `<#>`), defaults the metric from the index definition, and adds `key_field @@@ pdb.all()` when the relation has no ParadeDB predicate.
- `l2_distance` / `cosine_distance` / `inner_product` / `vector_distance` Arel builder methods and `pdb_l2_distance` / `pdb_cosine_distance` / `pdb_inner_product` / `pdb_vector_distance` attribute predications.
- `examples/vector_search` example. `examples/hybrid_rrf` now uses the native vector support instead of `neighbor`, and `examples/rag` retrieval combines full-text search with `nearest`.

### Changed

- **BREAKING**: Renamed the `bm25`-named migration helpers to `paradedb`: `add_bm25_index` is now `add_paradedb_index`, `remove_bm25_index` is now `remove_paradedb_index`, and `reindex_bm25` is now `reindex_paradedb_index`. The old names were removed; update migrations and `schema.rb` files to the new names.
- **BREAKING**: Index creation always emits `USING paradedb`, which requires pg_search 0.25.0+. There is no option to select the legacy `bm25` access method.
- **BREAKING**: The default index name is now `<table>_search_idx` (previously `<table>_bm25_idx`), and the index generator emits `Create<Model>SearchIndex` migrations named `create_<table>_search_index.rb`.

## [0.9.0] - 2026-07-14

### Added

- Allow SQL/Arel function nodes as `match_all` and `match_any` query arguments.

### Changed

- **BREAKING**: Restrict match APIs to a single query argument.
- **BREAKING**: Rename relation query methods `matching_all` and `matching_any`
  to `match_all` and `match_any`.

### Removed

- **BREAKING**: Removed max_term_freq from the more_like_this API.

## [0.8.0] - 2026-06-15

### Changed

- **BREAKING**: The `Tokenizer` class is now namespaced as `ParadeDB::Tokenizer`. Update references from `Tokenizer.simple(...)` to `ParadeDB::Tokenizer.simple(...)`. Schema dumps (`schema.rb`) now emit the fully-qualified constant.

## [0.7.0] - 2026-04-21

### Changed

- **BREAKING**: Use function based approach for specifying tokenizers: `Tokenizer.simple(options: {alias: "description_simple"})`

## [0.6.0] - 2026-04-14

### Added

- Support concurrent BM25 index creation via `concurrently:` in `create_paradedb_index` and `add_bm25_index`

## [0.5.0] - 2026-04-14

### Added

- Support partial indexes via `where:` in `add_bm25_index` and `ParadeDB::Index`

### Fixed

- Allow aliased indexed expressions like `"(rating + 1)" => { alias: "rating" }`

## [0.4.0] - 2026-04-09

### Changed

- Removed unnecessary validation from non-exact aggregate queries without `over()`
- `change` migrations now auto-reverse `create_paradedb_index` and `add_bm25_index`, while irreversible ParadeDB migration helpers raise explicit rollback errors

## [0.3.0] - 2026-03-23

### Removed

- **BREAKING**: Removed `has_paradedb_index` class attribute. It had no
  effect on library behavior. Remove `self.has_paradedb_index = true`
  from your models.

### Changed

- **BREAKING**: `near` now accepts a chainable `ParadeDB.proximity(...).within(...)`
  clause to support the full proximity API

## [0.2.0] - 2026-03-13

### Added

- Rails 7.2 support and CI coverage
- New search/query APIs: `regex_phrase`, `phrase_prefix`, `parse`,
  grouped `aggregate_by`, and `ParadeDB::Query.regex`
- Expanded snippet support with `with_snippets` and
  `with_snippet_positions`
- ParadeDB diagnostics helpers:
  `paradedb_indexes`, `paradedb_index_segments`,
  `paradedb_verify_index`, and `paradedb_verify_all_indexes`
- Additional aggregation helpers:
  `percentiles`, `histogram`, `date_histogram`, `top_hits`, and
  `filtered`
- Support for passing regexes into proximity queries using
  `ParadeDB.regex_term`

### Changed

- Fuzzy search controls are now flattened across the relation and Arel
  DSLs with direct `distance`, `prefix`, and
  `transposition_cost_one` options
- `matching_all` and `matching_any` now accept explicit `tokenizer:`
  overrides
- Runtime index validation now includes index-class discovery, drift
  checks, indexed-field validation, and model helpers for
  `paradedb_index_classes`, `paradedb_indexed_fields`,
  `paradedb_key_field`, and `paradedb_index_name`
- Facet and aggregation APIs now support `exact:` controls for exact
  versus windowed execution
- README, examples, and Arel documentation were expanded to cover the
  newer query, snippet, aggregation, and diagnostics APIs

### Fixed

- Search/runtime tokenizer handling now renders tokenizer SQL safely and
  validates unsupported tokenizer and facet combinations earlier

### Removed

- **BREAKING**: `near_regex` has been removed in favor of calling
  `near` with a regex argument using `ParadeDB.regex_term`

## [0.1.0] - 2026-02-07

### Added

- Initial `rails-paradedb` release.
- ActiveRecord model integration with ParadeDB entrypoints:
  `search`, `more_like_this`, `with_facets`, `facets`, `with_agg`,
  and `facets_agg`
- ActiveRecord relation search API with ParadeDB operators:
  `matching_all`, `matching_any`, `excluding`, `phrase`, `fuzzy`, `regex`,
  `term`, `near`, `phrase_prefix`, `more_like_this`, `parse`, `match_all`
- `exists`, `range`, and `term_set` helpers across relation and Arel DSLs
- `with_score` and `with_snippet` decorators
- Highlighting expansion with `with_snippets` and
  `with_snippet_positions`
- Faceting support: `facets` and `with_facets`
- Named aggregation helpers:
  `ParadeDB::Aggregations`, `facets_agg`, `with_agg`, and `aggregates`
- Arel integration with custom builder and visitor support
- BM25 index DSL with multi-tokenizer field configs, per-field options,
  tokenizer aliases, and `index_options`
- Migration helper support for creating/replacing/removing/reindexing BM25
  indexes (`create_paradedb_index`, `replace_paradedb_index`,
  `add_bm25_index`, `remove_bm25_index`, and `reindex_bm25`)
- Runtime safety checks for PostgreSQL adapter compatibility, index drift
  validation mode (`:off`, `:warn`, `:raise`), field-index validation, and
  class method collision detection
- PostgreSQL adapter guards and integration test suite
- Runnable examples for quickstart, faceted search, autocomplete,
  more-like-this, hybrid RRF, and RAG

### Changed

- `with_agg`/`facets_agg` now execute one `pdb.agg(...)` call per named
  aggregation to match ParadeDB aggregate parser constraints
- README coverage was tightened for query and highlighting APIs

### Fixed

- Schema dump/load round-trip for tokenizer configuration and index options
  (including `target_segment_count`)

[0.11.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.11.0
[0.10.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.10.0
[0.9.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.9.0
[0.8.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.8.0
[0.7.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.7.0
[0.6.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.6.0
[0.5.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.5.0
[0.4.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.4.0
[0.3.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.3.0
[0.2.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.2.0
[0.1.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.1.0
