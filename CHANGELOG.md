# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Pending.

## [0.1.0] - 2026-02-07

### Added

- Initial `rails-paradedb` release.
- ActiveRecord search API with ParadeDB operators:
  - `matching_all`, `matching_any`, `excluding`
  - `phrase`, `fuzzy`, `regex`, `term`, `near`, `phrase_prefix`
  - `more_like_this`, `parse`, `match_all`
- `with_score` and `with_snippet` decorators.
- Faceting support:
  - `facets` (terminal hash result)
  - `with_facets` (rows + facet metadata)
- Arel integration with custom builder and visitor support.
- PostgreSQL adapter guards and integration test suite.

[Unreleased]: https://github.com/paradedb/rails-paradedb/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/paradedb/rails-paradedb/releases/tag/v0.1.0
