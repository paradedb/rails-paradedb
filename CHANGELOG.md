# Changelog
<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- `exists`, `range`, and `term_set` query helpers in relation and Arel DSLs.
- Typed named aggregation helpers:
  `ParadeDB::Aggregations`, `facets_agg`, `with_agg`, and `aggregates`.
- Highlighting expansion with `with_snippets` and `with_snippet_positions`.
- Structured BM25 index DSL enhancements:
  multi-tokenizer field configs and `index_options` support.

### Changed

- `with_agg`/`facets_agg` now execute one `pdb.agg(...)` call per named
  aggregation to match ParadeDB aggregate parser constraints.
- README coverage was tightened for query and highlighting APIs.

### Fixed

- Schema dump/load round-trip for tokenizer configuration and index options
  (including `target_segment_count`).

## [0.1.0] - 2026-02-07

### Added

- Initial `rails-paradedb` release.
- ActiveRecord search API with ParadeDB operators:
  `matching_all`, `matching_any`, `excluding`, `phrase`, `fuzzy`, `regex`,
  `term`, `near`, `phrase_prefix`, `more_like_this`, `parse`, `match_all`.
- `with_score` and `with_snippet` decorators.
- Faceting support: `facets` and `with_facets`.
- Arel integration with custom builder and visitor support.
- PostgreSQL adapter guards and integration test suite.

[0.1.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.1.0
