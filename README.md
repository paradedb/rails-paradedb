# rails-paradedb

[![CI](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml/badge.svg)](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/paradedb/rails-paradedb?color=blue)](https://github.com/paradedb/rails-paradedb?tab=MIT-1-ov-file#readme)
[![Slack URL](https://img.shields.io/badge/Join%20Slack-purple?logo=slack&link=https%3A%2F%2Fjoin.slack.com%2Ft%2Fparadedbcommunity%2Fshared_invite%2Fzt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)](https://join.slack.com/t/paradedbcommunity/shared_invite/zt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)
[![X URL](https://img.shields.io/twitter/url?url=https%3A%2F%2Ftwitter.com%2Fparadedb&label=Follow%20%40paradedb)](https://x.com/paradedb)

[ParadeDB](https://paradedb.com) — simple, Elastic-quality search for Postgres — integration for ActiveRecord.

For complete ParadeDB documentation, see [docs.paradedb.com](https://docs.paradedb.com/).

## Status

Work in progress.

## Requirements & Compatibility

| Component  | Version                          |
|------------|----------------------------------|
| Ruby       | 4.0+                             |
| Rails      | 8.1+                             |
| ParadeDB   | 0.21.* (tested on 0.21.4)        |
| PostgreSQL | 17, 18 (with ParadeDB extension) |

**Note**: This gem requires ActiveRecord. Both the user-facing DSL and the Arel layer delegate SQL value quoting to `ActiveRecord::Base.connection.quote` for type safety and proper escaping.

## Installation

This gem is not published yet. Local development uses the code in this repository directly.

## Quick Start

Enable ParadeDB on a model:

```ruby
class Product < ApplicationRecord
  include ParadeDB::Model
  self.has_paradedb_index = true
end
```

Basic search:

```ruby
# Match ALL terms (conjunction)
Product.search(:description).matching_all("running", "shoes")

# Match ANY term (disjunction)
Product.search(:description).matching_any("wireless", "bluetooth")
```

Search with filters:

```ruby
Product.search(:description).matching_all("shoes")
  .where(in_stock: true)
  .order(price: :asc)
```

Scoring and snippets:

```ruby
Product.search(:description).matching_all("running", "shoes")
  .with_score
  .with_snippet(:description, start_tag: "<b>", end_tag: "</b>")
  .order(search_score: :desc)
```

## Query Types

| Method | Operator | Description |
|--------|----------|-------------|
| `matching_all("a", "b")` | `&&&` | Match ALL terms (AND) |
| `matching_any("a", "b")` | `\|\|\|` | Match ANY term (OR) |
| `phrase("a b", slop: n)` | `###` | Phrase match with optional word distance |
| `term("value")` | `===` | Exact token match (see below) |
| `fuzzy("term", distance: n)` | `===` | Fuzzy match with edit distance |
| `regex("pattern")` | `@@@` | Regex pattern match |
| `near("a", "b", distance: n)` | `@@@` | Proximity search |
| `phrase_prefix("a", "b")` | `@@@` | Autocomplete/prefix matching |
| `more_like_this(id, fields: [...])` | `@@@` | Find similar documents |

### When to use `term` vs `matching_all`

- **`matching_all`** / **`matching_any`**: Standard full-text search. The query string is tokenized and matched against indexed tokens. Use for natural language queries like `"running shoes"`.

- **`term`**: Exact token match without further tokenization. The query is treated as a finalized token. Use when you need precise control, such as matching a specific category value or status field.

```ruby
# Full-text search - tokenizes "running shoes" into ["running", "shoes"]
Product.search(:description).matching_all("running shoes")

# Exact term - matches the literal token "active" (case-sensitive to indexed form)
Product.search(:status).term("active")
```

## Arel Layer

The user API is built on top of a dedicated Arel layer that provides an AST and SQL renderer for ParadeDB operators.

### Quickstart

```ruby
require "parade_db/arel"

arel = ParadeDB::Arel::Builder.new(:products)

predicate = arel.match(:description, "running", "shoes")
  .and(arel.regex(:description, "run.*"))
  .and(arel.term(:in_stock, true))

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
