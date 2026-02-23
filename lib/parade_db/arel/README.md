# ParadeDB Arel Guide

This guide covers the low-level Arel API used by `rails-paradedb`.
Use it when you need explicit AST composition or direct SQL rendering.

## Quickstart

```ruby
require "parade_db/arel"

arel = ParadeDB::Arel::Builder.new(:products)

predicate = arel.match(:description, "running", "shoes")
               .and(arel.regex(:description, "run.*"))
               .and(arel.term(:in_stock, true))

sql = ParadeDB::Arel.to_sql(predicate, Product.connection)
# => ("products"."description" &&& 'running shoes' AND "products"."description" @@@ pdb.regex('run.*') AND "products"."in_stock" === TRUE)

Product.where(Arel.sql(sql))
```

Render any node with `ParadeDB::Arel.to_sql(node)`. All nodes respond to
`.and`, `.or`, and `.not`.

## Builder Methods

| Method | ParadeDB SQL |
|--------|--------------|
| `match(column, *terms, distance:, prefix:, transposition_cost_one:, boost: nil)` | `column &&& 'a b'::pdb.fuzzy(...)::pdb.boost(N)` |
| `match_any(column, *terms, distance:, prefix:, transposition_cost_one:, boost: nil)` | `column \|\|\| 'a b'::pdb.fuzzy(...)::pdb.boost(N)` |
| `phrase(column, text, slop: n)` | `column ### 'text'::pdb.slop(n)` |
| `term(column, term, distance:, prefix:, transposition_cost_one:, boost: nil)` | `column === 'term'::pdb.fuzzy(...)::pdb.boost(N)` |
| `term_set(column, *terms)` | `column @@@ pdb.term_set(ARRAY[...])` |
| `regex(column, pattern)` | `column @@@ pdb.regex('pattern')` |
| `near(column, a, b, distance:)` | `column @@@ ('a' ## d ## 'b')` |
| `phrase_prefix(column, *terms)` | `column @@@ pdb.phrase_prefix(ARRAY['a','b'])` |
| `full_text(column, expr)` | `column @@@ expr` (raw right-hand value) |
| `match_all(column)` | `column @@@ pdb.all()` |
| `exists(column)` | `column @@@ pdb.exists()` |
| `range(column, value = nil, gte:, gt:, lte:, lt:, type:)` | `column @@@ pdb.range(int8range(3, 5, '[)'))` |
| `more_like_this(column, key, fields: [:f1, :f2])` | `column @@@ pdb.more_like_this(key, ARRAY['f1','f2'])` |
| `score(key_field)` | `pdb.score(key_field)` |
| `snippet(column, start, finish, max)` | `pdb.snippet(column, start, finish, max)` |
| `snippets(column, start_tag:, end_tag:, max_num_chars:, limit:, offset:, sort_by:)` | `pdb.snippets(column, ...)` |
| `snippet_positions(column)` | `pdb.snippet_positions(column)` |
| `agg(json)` | `pdb.agg(json)` |

`Builder#[]` returns a column node for manual composition: `arel[:description]`.

## Composition

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
