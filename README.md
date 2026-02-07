# rails-paradedb

[![Gem Version](https://img.shields.io/gem/v/rails-paradedb)](https://rubygems.org/gems/rails-paradedb)
[![CI](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml/badge.svg)](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/paradedb/rails-paradedb?color=blue)](https://github.com/paradedb/rails-paradedb?tab=MIT-1-ov-file#readme)
[![Slack URL](https://img.shields.io/badge/Join%20Slack-purple?logo=slack&link=https%3A%2F%2Fjoin.slack.com%2Ft%2Fparadedbcommunity%2Fshared_invite%2Fzt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)](https://join.slack.com/t/paradedbcommunity/shared_invite/zt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)
[![X URL](https://img.shields.io/twitter/url?url=https%3A%2F%2Ftwitter.com%2Fparadedb&label=Follow%20%40paradedb)](https://x.com/paradedb)

[ParadeDB](https://paradedb.com) — simple, Elastic-quality search for Postgres — integration for ActiveRecord.

For complete ParadeDB documentation, see [docs.paradedb.com](https://docs.paradedb.com/).

## Requirements & Compatibility

| Component  | Version                          |
|------------|----------------------------------|
| Ruby       | 3.2+                             |
| Rails      | 8.0+                             |
| ParadeDB   | 0.21.* (tested on 0.21.4)        |
| PostgreSQL | 17, 18 (with ParadeDB extension) |

**Note**: This gem requires ActiveRecord with PostgreSQL. The DSL and Arel layer delegate SQL value quoting to `ActiveRecord::Base.connection.quote` for type safety and proper escaping.

## Installation

Add to your Gemfile:

```ruby
gem "rails-paradedb"
```

Then run:

```bash
bundle install
```

## Quick Start

Enable ParadeDB on a model:

```ruby
class Product < ApplicationRecord
  include ParadeDB::Model
end
```

Search with a simple query:

```ruby
Product.search(:description).matching_all("shoes")
```

Check out some examples:

- [Quick Start](examples/quickstart/quickstart.rb)
- [Faceted Search](examples/faceted_search/faceted_search.rb)
- [Autocomplete](examples/autocomplete/autocomplete.rb)
- [More Like This](examples/more_like_this/more_like_this.rb)
- [Hybrid Search (RRF)](examples/hybrid_rrf/hybrid_rrf.rb)
- [RAG](examples/rag/rag.rb)

## BM25 Index

> **Note:** This gem does not yet provide a Rails DSL for BM25 index creation or migrations. This feature will be added in a future version.
>
> For now, please refer to the [ParadeDB documentation](https://docs.paradedb.com/) for index creation, migrations, tokenizers, and stemmers configuration.

## Query Types

For a full list of supported query types and advanced options, please refer to the [ParadeDB Query Builder Documentation](https://docs.paradedb.com/documentation/query-builder/overview).

### Basic Search

Simple full-text search with `&&&` (AND) operator:

```ruby
# Single term
Product.search(:description).matching_all("shoes")

# Multiple terms (AND)
Product.search(:description).matching_all("running", "shoes")
```

### OR Search

Match any of the provided terms:

```ruby
# Match ANY term (OR)
Product.search(:description).matching_any("wireless", "bluetooth")
```

### Phrase Search

Match exact phrases with optional slop (word distance):

```ruby
# Exact phrase
Product.search(:description).phrase("running shoes")

# Phrase with slop (allow up to 2 words between)
Product.search(:description).phrase("running shoes", slop: 2)
```

### Fuzzy Search

Match terms with typo tolerance (Levenshtein distance):

```ruby
# Fuzzy match with distance 1 (default)
Product.search(:description).fuzzy("shoez")

# Fuzzy match with distance 2, prefix matching, and boost
Product.search(:description).fuzzy("runing", distance: 2, prefix: true, boost: 1.5)
```

### Term Query

Match exact tokens without tokenization:

```ruby
Product.search(:category).term("electronics")

# With boost
Product.search(:category).term("electronics", boost: 2.0)
```

### When to use `term` vs `matching_all`

- **`matching_all`** / **`matching_any`**: Standard full-text search. The query string is tokenized and matched against indexed tokens. Use for natural language queries like `"running shoes"`.

- **`term`**: Exact token match without further tokenization. The query is treated as a finalized token. Use when you need precise control, such as matching a specific category value or status field.

```ruby
# Full-text search - tokenizes "running shoes" into ["running", "shoes"]
Product.search(:description).matching_all("running shoes")

# Exact term - matches the literal token "active" (case-sensitive to indexed form)
Product.search(:status).term("active")
```

### Regex Query

Match terms using a regular expression:

```ruby
Product.search(:description).regex("run.*")
```

### Match All

Return all documents (useful with facets):

```ruby
Product.search(:id).match_all
```

### More Like This

Find similar documents based on term frequency analysis:

```ruby
# Similar to a specific document by ID
Product.more_like_this(42, fields: [:description])

# Similar to a custom document (JSON string)
Product.more_like_this('{"description": "comfortable running shoes"}')

# Advanced MLT options
Product.more_like_this(
  42,
  fields: [:description],
  min_term_freq: 2,
  max_query_terms: 10,
  min_doc_freq: 1,
  max_term_freq: 100,
  max_doc_freq: 1000,
  min_word_length: 3,
  max_word_length: 15,
  stopwords: %w[the a]
)
```

**Combining with other filters:**

```ruby
# Combine with standard filters
Product.more_like_this(42, fields: [:description])
       .where(in_stock: true)
       .where("rating >= ?", 4)

# Chain with other querysets
Product.more_like_this(42, fields: [:description])
       .where.not(id: 42)  # Exclude the source document itself
       .order(rating: :desc)
       .limit(10)
```

### Excluding Terms

Exclude documents matching specific terms:

```ruby
Product.search(:description).matching_all("shoes").excluding("cheap", "budget")
```

### Proximity Search

Find terms within a specified word distance:

```ruby
Product.search(:description).near("running", "shoes", distance: 3)
```

### Phrase Prefix (Autocomplete)

Match terms as prefixes for autocomplete functionality:

```ruby
Product.search(:description).phrase_prefix("run", "sh")
```

### Parse Query

Use ParadeDB's query string syntax:

```ruby
Product.search(:description).parse("running AND shoes", lenient: true)
```

## Annotations

### BM25 Score

Get the relevance score for each result. For more information on how scores are calculated, see [BM25 Scoring](https://docs.paradedb.com/documentation/sorting/score).

```ruby
Product.search(:description).matching_all("shoes")
       .with_score
       .order(search_score: :desc)

# Access the score on results
results.each { |product| puts product.search_score }
```

### Snippet

Get highlighted text snippets. For more details on snippet configuration, see [Highlighting](https://docs.paradedb.com/documentation/full-text/highlight).

```ruby
Product.search(:description).matching_all("shoes")
       .with_snippet(:description, start_tag: "<b>", end_tag: "</b>")

# Access the snippet on results
results.each { |product| puts product.description_snippet }
```

Snippet options:

| Option       | Description                    |
|--------------|--------------------------------|
| `start_tag`  | Opening highlight tag          |
| `end_tag`    | Closing highlight tag          |
| `max_chars`  | Maximum snippet length         |

### Combining Score and Snippet

```ruby
Product.search(:description).matching_all("running", "shoes")
       .with_score
       .with_snippet(:description, start_tag: "<mark>", end_tag: "</mark>")
       .order(search_score: :desc)
```

## Faceted Search

For a full list of supported aggregations and advanced options, please refer to the [ParadeDB Aggregations Documentation](https://docs.paradedb.com/documentation/aggregates/overview).

### Requirements

The `.with_facets()` method has specific requirements:

**When getting rows + facets:**

- **MUST** have a ParadeDB search filter
- **MUST** call `.order()` on the relation
- **MUST** call `.limit()` on the relation

**When getting facets only (`.facets()`):**

- **MUST** have a ParadeDB search filter
- No ordering or limit required

**Why these requirements?**

ParadeDB's aggregation uses window functions (`pdb.agg() OVER ()`) which require ordered, limited result sets when combined with row data. Without ordering and limits, PostgreSQL cannot efficiently compute the aggregations.

### Basic Usage

Get aggregated counts alongside results:

```ruby
# Correct: Has filter, ordering, and limit
relation = Product.search(:description).matching_all("shoes")
                  .with_facets(:category)
                  .order(:id)
                  .limit(10)

rows = relation.to_a           # Product records
facets = relation.facets       # Facet buckets hash
# facets = {"category" => {"buckets" => [{"key" => "footwear", "doc_count" => 5}, ...]}}
```

```ruby
# This will raise ParadeDB::FacetQueryError
relation = Product.search(:description).matching_all("shoes")
                  .with_facets(:category)  # Missing order() and limit()!
```

### Facets Only (No Rows)

```ruby
# No ordering/limit needed when only fetching facets
facets = Product.search(:description).matching_all("shoes")
                .facets(:category)
```

### Multiple Facet Fields

```ruby
relation = Product.search(:description).matching_all("shoes")
                  .with_facets(:category, :rating)
                  .order(:id)
                  .limit(10)

facets = relation.facets
# facets = {"category" => {...}, "rating" => {...}}
```

### Facet Options

```ruby
relation = Product.search(:description).matching_all("shoes")
                  .with_facets(
                    :category,
                    size: 20,           # Number of buckets (default: 10)
                    order: "-count",    # Sort order: count, -count, key, -key
                    missing: "Unknown"  # Value for documents without the field
                  )
                  .order(:rating)
                  .limit(20)
```

### Custom Aggregation JSON

```ruby
facets = Product.search(:description).matching_all("shoes")
                .facets(agg: { "value_count" => { "field" => "id" } })

# Works with rows too
relation = Product.search(:description).matching_all("shoes")
                  .with_facets(agg: { "value_count" => { "field" => "id" } })
                  .order(:id)
                  .limit(10)

# When agg: is present, field/size/order/missing are ignored for payload generation.
```

### Combining with Other ActiveRecord Methods

```ruby
# Filter, annotate, order, limit, then facet
relation = Product.search(:description).matching_all("running", "shoes")
                  .where("price < ?", 100)
                  .with_score
                  .with_facets(:category, :brand)
                  .order(search_score: :desc)
                  .limit(20)

rows = relation.to_a
facets = relation.facets

# Works with includes
relation = Product.search(:description).matching_all("shoes")
                  .includes(:reviews)
                  .with_facets(:category)
                  .order(:id)
                  .limit(10)
```

### Common Errors and Solutions

#### Error: "ParadeDB::FacetQueryError - with_facets requires order() and limit()"

```ruby
# Missing ordering
Product.search(:description).matching_all("shoes")
       .with_facets(:category)
       .limit(10)  # Missing order()!

# Missing limit
Product.search(:description).matching_all("shoes")
       .with_facets(:category)
       .order(:id)  # Missing limit()!

# Both ordering and limit
Product.search(:description).matching_all("shoes")
       .with_facets(:category)
       .order(:id)
       .limit(10)

# Or use facets() for facets only
Product.search(:description).matching_all("shoes")
       .facets(:category)
```

## ActiveRecord Integration

Works seamlessly with ActiveRecord's query interface:

```ruby

# Multiple search fields (AND composition)
Product.search(:description).matching_all("running")
       .search(:category).phrase("Footwear")

# OR composition across fields
left = Product.search(:description).matching_all("shoes")
right = Product.search(:category).matching_all("footwear")
left.or(right)

# Preload associations
Product.search(:description).matching_all("shoes")
       .preload(:reviews)

# Chain with standard filters
Product.search(:description).matching_all("shoes")
       .where(in_stock: true)
       .where("rating >= ?", 4)

# Chain with exclusions
Product.search(:description).matching_all("shoes")
       .where.not(category: "clearance")
```

## Arel Layer

The user API is built on top of a dedicated Arel layer that provides an AST and SQL renderer for ParadeDB operators. This is useful for building complex queries in case the ActiveRecord Syntax is not enough. All of the ActiveRecord syntax is available in the Arel layer as well. 

### Quickstart

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

## Security

### SQL Injection Protection

rails-paradedb uses **ActiveRecord's quoting** for all search terms:

**Quoting Strategy:**

- All user input is quoted via `ActiveRecord::Base.connection.quote`
- Search terms use Arel's `Nodes.build_quoted()` for type-safe SQL generation
- This prevents SQL injection while maintaining compatibility with ParadeDB's full-text operators

**Implementation Details:**

All values flow through ActiveRecord's connection adapter quoting, which handles:
- String escaping (`'` → `''`)
- Type coercion (booleans, numbers)
- NULL handling

**Safety Guarantee:**

```ruby
# Even malicious input is safely escaped
user_query = "'; DROP TABLE products; --"
Product.search(:description).matching_all(user_query)
# The query is escaped and treated as a literal search term
```

## Documentation

- **ParadeDB Official Docs**: <https://docs.paradedb.com>
- **ParadeDB Website**: <https://paradedb.com>

## Contributing

Contribution and local development workflow live in [`CONTRIBUTING.md`](CONTRIBUTING.md).

Release process and policy live in [`RELEASE.md`](RELEASE.md).

## Support

If you're missing a feature or have found a bug, please open a
[GitHub Issue](https://github.com/paradedb/rails-paradedb/issues/new/choose).

To get community support, you can:

- Post a question in the [ParadeDB Slack Community](https://join.slack.com/t/paradedbcommunity/shared_invite/zt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)
- Ask for help on our [GitHub Discussions](https://github.com/paradedb/paradedb/discussions)

If you need commercial support, please [contact the ParadeDB team](mailto:sales@paradedb.com).

## License

rails-paradedb is licensed under the [MIT License](LICENSE).
