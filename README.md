# rails-paradedb

[![CI](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml/badge.svg)](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/paradedb/rails-paradedb?color=blue)](https://github.com/paradedb/rails-paradedb?tab=MIT-1-ov-file#readme)
[![Slack URL](https://img.shields.io/badge/Join%20Slack-purple?logo=slack&link=https%3A%2F%2Fjoin.slack.com%2Ft%2Fparadedbcommunity%2Fshared_invite%2Fzt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)](https://join.slack.com/t/paradedbcommunity/shared_invite/zt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)
[![X URL](https://img.shields.io/twitter/url?url=https%3A%2F%2Ftwitter.com%2Fparadedb&label=Follow%20%40paradedb)](https://x.com/paradedb)

[ParadeDB](https://paradedb.com) — simple, Elastic-quality search for Postgres — integration for ActiveRecord.

## Status

Work in progress. See `design-doc.md` for the current API proposal and scope.

## Requirements & Compatibility

Version details are still being finalized for this repository. ParadeDB and PostgreSQL must be installed and running with the ParadeDB extension enabled.

## Installation

This gem is not published yet. Local development uses the code in this repository directly.

## Quick Start

Enable ParadeDB on a model:

```ruby
class Product < ApplicationRecord
  include ParadeDB::Model
  self.has_parade_db_index = true
end
```

Basic search:

```ruby
Product.search(:description).matching("running", "shoes")
```

Search with filters:

```ruby
Product.search(:description).matching("shoes")
  .where(in_stock: true)
  .order(price: :asc)
```

Scoring and snippets:

```ruby
Product.search(:description).matching("running", "shoes")
  .with_score
  .with_snippet(:description, start_tag: "<b>", end_tag: "</b>")
  .order(search_score: :desc)
```

## Arel Layer

The user API is built on top of a dedicated Arel layer. See `AREL_README.md` for Arel node usage and SQL rendering.

## Query Types (Summary)

- `matching` / `matching(any: [...])`
- `phrase` with `slop`
- `fuzzy` with `distance`, `prefix`, and `boost`
- `term` for exact term match
- `regex`, `near`, `phrase_prefix`
- `similar_to`
- `with_score`, `with_snippet`
- `facets`, `with_facets`

For the full user-facing API, see `design-doc.md`.

## License

MIT. See `LICENSE`.
