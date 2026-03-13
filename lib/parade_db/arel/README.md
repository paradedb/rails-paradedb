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

| Method                                                                                               | ParadeDB SQL                                                                          |
| ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `match(column, *terms, tokenizer: nil, distance:, prefix:, transposition_cost_one:, boost: nil)`     | `column &&& 'a b'::pdb.whitespace::pdb.fuzzy(...)::pdb.boost(N)`                      |
| `match_any(column, *terms, tokenizer: nil, distance:, prefix:, transposition_cost_one:, boost: nil)` | `column \|\|\| 'a b'::pdb.whitespace::pdb.fuzzy(...)::pdb.boost(N)`                   |
| `phrase(column, text_or_terms, slop: n, tokenizer: nil)`                                             | `column ### 'text'::pdb.slop(n)::pdb.whitespace` / `### ARRAY['a', 'b']::pdb.slop(n)` |
| `term(column, term, distance:, prefix:, transposition_cost_one:, boost: nil)`                        | `column === 'term'::pdb.fuzzy(...)::pdb.boost(N)`                                     |
| `term_set(column, *terms)`                                                                           | `column @@@ pdb.term_set(ARRAY[...])`                                                 |
| `regex(column, pattern)`                                                                             | `column @@@ pdb.regex('pattern')`                                                     |
| `regex_phrase(column, *patterns, slop: nil, max_expansions: nil)`                                    | `column @@@ pdb.regex_phrase(ARRAY['a', 'b'], slop => 2)`                             |
| `near(column, *terms, anchor:, distance:, ordered: false)`                                           | `column @@@ ('a' ## d ## 'b')` / `(pdb.prox_array('a', 'b') ## d ## 'c')`             |
| `near(column, ParadeDB.regex('a'), 'b', anchor:, distance:)`                                         | `column @@@ (pdb.prox_array(pdb.prox_regex('a'), 'b') ## d ## 'c')`                   |
| `phrase_prefix(column, *terms, max_expansion: nil)`                                                  | `column @@@ pdb.phrase_prefix(ARRAY['a','b'][, 100])`                                 |
| `parse(column, query, lenient: nil, conjunction_mode: nil)`                                          | `column @@@ pdb.parse('q', lenient => true, conjunction_mode => true)`                |
| `full_text(column, expr)`                                                                            | `column @@@ expr` (raw right-hand value)                                              |
| `match_all(column)`                                                                                  | `column @@@ pdb.all()`                                                                |
| `exists(column)`                                                                                     | `column @@@ pdb.exists()`                                                             |
| `range(column, value = nil, gte:, gt:, lte:, lt:, type:)`                                            | `column @@@ pdb.range(int8range(3, 5, '[)'))`                                         |
| `range_term(column, value, relation: nil, range_type: nil)`                                          | `column @@@ pdb.range_term(1)` / `pdb.range_term('(1,2]'::int4range, 'Intersects')`   |
| `more_like_this(column, key, fields: [:f1, :f2])`                                                    | `column @@@ pdb.more_like_this(key, ARRAY['f1','f2'])`                                |
| `score(key_field)`                                                                                   | `pdb.score(key_field)`                                                                |
| `snippet(column, start, finish, max)`                                                                | `pdb.snippet(column, start, finish, max)`                                             |
| `snippets(column, start_tag:, end_tag:, max_num_chars:, limit:, offset:, sort_by:)`                  | `pdb.snippets(column, ...)`                                                           |
| `snippet_positions(column)`                                                                          | `pdb.snippet_positions(column)`                                                       |
| `agg(json, exact: nil)`                                                                              | `pdb.agg(json[, false])`                                                              |

`Builder#[]` returns a column node for manual composition: `arel[:description]`.

> **Note:** `Builder` has no access to ActiveRecord model metadata.
> When calling `range_term` with a `relation:`, you must pass `range_type:` explicitly.
> The `SearchMethods` layer (`.search(:col).range_term(...)`) auto-infers `range_type` from the column's SQL type.

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
