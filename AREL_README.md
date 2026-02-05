# ParadeDB Arel Layer

This is the implementation of **Layer 1 (Arel)** from `design-doc.md`. It provides an AST and SQL renderer for ParadeDB operators; the Rails/ActiveRecord DSL (Layer 2) will sit on top of this.

## Quickstart

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

## Builder Surface (power users)

| Method | ParadeDB SQL |
|--------|--------------|
| `match(column, *terms, boost: nil)` | `column &&& 'a b'::pdb.boost(N)` |
| `match_any(column, *terms)` | `column ||| 'a b'` |
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

## Composition

Boolean composition uses the standard helpers:

```ruby
fast = arel.match(:description, "running").and(arel.term(:rating, 4))
cheap = arel.match(:description, "budget")
predicate = fast.or(cheap.not)
```

`predicate` renders to:

```
(("products"."description" &&& 'running' AND "products"."rating" === 4) OR NOT ("products"."description" &&& 'budget'))
```

## Query Coverage Map

- Conjunction: `match` (&&&)
- Disjunction: `match_any` (|||)
- Phrase + slop: `phrase`
- Fuzzy/typo: `fuzzy`
- Exact term: `term`
- Regex: `regex`
- Proximity: `near`
- Phrase prefix / autocomplete: `phrase_prefix`
- Full-text escape hatch: `full_text`
- More-like-this: `more_like_this`
- Boost modifier: `boost:` on `match/term/fuzzy`
- Slop modifier: `slop:` on `phrase`
- Projections: `score`, `snippet`
- Aggregations: `agg`

These cover the ParadeDB operator matrix in the design doc; additional operators can be added by introducing a node class and handling it in `Visitor`.
