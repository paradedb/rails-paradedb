# rails-paradedb

[![CI](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml/badge.svg)](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/paradedb/rails-paradedb?color=blue)](https://github.com/paradedb/rails-paradedb?tab=MIT-1-ov-file#readme)
[![Slack URL](https://img.shields.io/badge/Join%20Slack-purple?logo=slack&link=https%3A%2F%2Fjoin.slack.com%2Ft%2Fparadedbcommunity%2Fshared_invite%2Fzt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)](https://join.slack.com/t/paradedbcommunity/shared_invite/zt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)
[![X URL](https://img.shields.io/twitter/url?url=https%3A%2F%2Ftwitter.com%2Fparadedb&label=Follow%20%40paradedb)](https://x.com/paradedb)

[ParadeDB](https://paradedb.com) — simple, Elastic-quality search for Postgres — integration for ActiveRecord.

## Status

Work in progress.

## Requirements & Compatibility

| Component  | Version                          |
|------------|----------------------------------|
| Ruby       | 4.0+                             |
| Rails      | 8.1+                             |
| ParadeDB   | 0.21.* (tested on 0.21.4)        |
| PostgreSQL | 17, 18 (with ParadeDB extension) |

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

## Query Types (Summary)

- `matching` / `matching(any: [...])`
- `phrase` with `slop`
- `fuzzy` with `distance`, `prefix`, and `boost`
- `term` for exact term match
- `regex`, `near`, `phrase_prefix`
- `similar_to`
- `with_score`, `with_snippet`
- `facets`, `with_facets`

## Arel Layer

The user API is built on top of a dedicated Arel layer that provides an AST and SQL renderer for ParadeDB operators.

### Quickstart

```ruby
require "parade_db/arel"

arel = ParadeDB::Arel::Builder.new(:products)

predicate = arel.match(:description, "running", "shoes")
  .and(arel.regex(:description, "run.*"))
  .and(arel.match(:in_stock, true))

sql = ParadeDB::Arel.to_sql(predicate)
# => ("products"."description" &&& 'running shoes' AND "products"."description" @@@ pdb.regex('run.*') AND "products"."in_stock" === true)
```

Render any node with `ParadeDB::Arel.to_sql(node)`. All nodes respond to `.and`, `.or`, and `.not`.

### Builder Methods

| Method | ParadeDB SQL |
|--------|--------------|
| `match(column, *terms, boost: nil)` | `column &&& 'a b'::pdb.boost(N)` |
| `match_any(column, *terms)` | `column \|\|\| 'a b'` |
| `phrase(column, text, slop: n)` | `column ### 'text'::pdb.slop(n)` |
| `term(column, term, boost: nil)` | `column === 'term'::pdb.boost(N)` |
| `fuzzy(column, term, distance:, prefix:, boost:)` | `column === 'term'::pdb.fuzzy(d[, "true"])::pdb.boost(N)` |
| `regex(column, pattern)` | `column @@@ pdb.regex('pattern')` |
| `near(column, a, b, distance:)` | `column @@@ ('a' ## d ## 'b')` |
| `phrase_prefix(column, *terms)` | `column @@@ pdb.phrase_prefix(ARRAY['a','b'])` |
| `full_text(column, expr)` | `column @@@ expr` (raw right-hand value) |
| `more_like_this(column, key, fields: [:f1, :f2])` | `column @@@ pdb.more_like_this(key, ARRAY['f1','f2'])` |
| `score(key_field)` | `pdb.score(key_field)` |
| `snippet(column, start, finish, max)` | `pdb.snippet(column, start, finish, max)` |
| `agg(json)` | `pdb.agg(json)` |

`Builder#[]` returns a column node for manual composition: `arel[:description]`.

### Composition

Boolean composition uses the standard helpers:

```ruby
fast = arel.match(:description, "running").and(arel.term(:rating, 4))
cheap = arel.match(:description, "budget")
predicate = fast.or(cheap.not)
```

`predicate` renders to:

```sql
(("products"."description" &&& 'running' AND "products"."rating" === 4) OR NOT ("products"."description" &&& 'budget'))
```

## License

MIT. See `LICENSE`.
