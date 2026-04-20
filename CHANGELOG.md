# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/paradedb/rails-paradedb/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.6.0
[0.5.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.5.0
[0.4.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.4.0
[0.3.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.3.0
[0.2.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.2.0
[0.1.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.1.0
