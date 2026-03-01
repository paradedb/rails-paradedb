# Changelog

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/paradedb/rails-paradedb/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.1.0
