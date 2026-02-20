# rails-paradedb

[![Gem Version](https://img.shields.io/gem/v/rails-paradedb)](https://rubygems.org/gems/rails-paradedb)
[![CI](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml/badge.svg)](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/paradedb/rails-paradedb?color=blue)](https://github.com/paradedb/rails-paradedb?tab=MIT-1-ov-file#readme)
[![Slack URL](https://img.shields.io/badge/Join%20Slack-purple?logo=slack&link=https%3A%2F%2Fjoin.slack.com%2Ft%2Fparadedbcommunity%2Fshared_invite%2Fzt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)](https://join.slack.com/t/paradedbcommunity/shared_invite/zt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)
[![X URL](https://img.shields.io/twitter/url?url=https%3A%2F%2Ftwitter.com%2Fparadedb&label=Follow%20%40paradedb)](https://x.com/paradedb)

[ParadeDB](https://paradedb.com) — simple, Elastic-quality search for Postgres — **BM25 full-text** integration for ActiveRecord.

For complete ParadeDB documentation, see [docs.paradedb.com](https://docs.paradedb.com/).

## Requirements & Compatibility

| Component  | Version                          |
|------------|----------------------------------|
| Ruby       | 3.2+                             |
| Rails      | 8.1+                             |
| ParadeDB   | 0.21.0+                          |
| PostgreSQL | 17+    (with ParadeDB extension) |

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
- [RAG](examples/rag/rag.rb)

## BM25 Index

Generate an index class and migration:

```bash
rails g parade_db:index Product description category rating
```

Or define one manually:

```ruby
class ProductIndex < ParadeDB::Index
  self.table_name = :products
  self.key_field = :id
  self.index_options = { target_segment_count: 17 }
  self.fields = {
    id: {},
    description: {
      tokenizers: [
        { tokenizer: :literal },
        { tokenizer: :simple, alias: "description_simple", filters: [:lowercase] }
      ]
    },
    category: { tokenizer: :literal },
    "metadata->>'color'": { tokenizer: :literal, alias: "metadata_color" },
    metadata: { fast: true, expand_dots: false }
  }
end
```

Field config supports:

- `tokenizer` for a single tokenizer entry.
- `tokenizers` for multiple tokenizer entries on the same source field.
- `args`, `named_args`, `filters`, `stemmer`, `alias` inside tokenizer entries.
- field options such as `fast`, `record`, `normalizer`, `expand_dots`.

Create/remove it in a migration:

```ruby
class AddProductBm25Index < ActiveRecord::Migration[8.1]
  def up
    create_paradedb_index(ProductIndex, if_not_exists: true)
  end

  def down
    remove_bm25_index :products, name: :products_bm25_idx, if_exists: true
  end
end
```

Available migration helpers:

- `create_paradedb_index(index_class_or_name, if_not_exists: false)`
- `replace_paradedb_index(index_class_or_name)`
- `add_bm25_index(table, fields:, key_field:, name: nil, index_options: nil, if_not_exists: false)`
- `remove_bm25_index(table, name: nil, if_exists: false)`
- `reindex_bm25(table, name: nil, concurrently: false)`

### Index Validation Mode

Runtime index drift validation is controlled by `ParadeDB.index_validation_mode`.
Default is `:off` (no runtime drift checks).

```ruby
ParadeDB.index_validation_mode = :warn  # log drift warnings
ParadeDB.index_validation_mode = :raise # raise ParadeDB::IndexDriftError on drift
ParadeDB.index_validation_mode = :off   # disable drift checks (default)
```

## Query Types

For advanced options, see [ParadeDB Query Builder Documentation](https://docs.paradedb.com/documentation/query-builder/overview) and the runnable scripts in [`examples/`](examples).

```ruby
# Full-text
Product.search(:description).matching_all("running shoes")
Product.search(:description).matching_any("wireless", "bluetooth")
Product.search(:description).phrase("running shoes", slop: 2)
Product.search(:description).fuzzy("runing", distance: 2, prefix: true, boost: 1.5)
Product.search(:description).regex("run.*")
Product.search(:description).parse("running AND shoes", lenient: true)

# Exact token matching
Product.search(:category).term("electronics", boost: 2.0)
Product.search(:category).term_set("electronics", "audio")

# Other predicates
Product.search(:description).excluding("cheap", "budget")
Product.search(:description).near("running", "shoes", distance: 3)
Product.search(:description).phrase_prefix("run", "sh")
Product.search(:id).match_all
Product.search(:id).exists
Product.search(:rating).range(gte: 3, lt: 5)

# Similarity
Product.more_like_this(42, fields: [:description])
```

## Annotations

See [BM25 Scoring](https://docs.paradedb.com/documentation/sorting/score) and [Highlighting](https://docs.paradedb.com/documentation/full-text/highlight) for full function details.

```ruby
Product.search(:description).matching_all("shoes").with_score
Product.search(:description).matching_all("shoes").with_snippet(:description, start_tag: "<b>", end_tag: "</b>", max_chars: 80)
Product.search(:description).matching_all("running").with_snippets(:description, max_chars: 15, limit: 2, offset: 0, sort_by: :position)
Product.search(:description).matching_all("running").with_snippet_positions(:description)
```

## Faceted Search

For supported aggregate functions and JSON shapes, see [ParadeDB Aggregations Documentation](https://docs.paradedb.com/documentation/aggregates/overview).

`with_facets(...)` requires:

- an existing ParadeDB predicate
- `.order(...)`
- `.limit(...)`

```ruby
# Rows + facets
relation = Product.search(:description).matching_all("shoes")
                  .with_facets(:category, size: 10)
                  .order(:id)
                  .limit(10)
rows = relation.to_a
facets = relation.facets

# Facets only
facets_only = Product.search(:description).matching_all("shoes")
                     .facets(:category)

# Named aggregation helpers
aggs = Product.search(:description).matching_all("shoes")
              .facets_agg(
                docs: ParadeDB::Aggregations.value_count(:id),
                avg_rating: ParadeDB::Aggregations.avg(:rating)
              )
```

## ActiveRecord Integration

ParadeDB scopes compose with regular ActiveRecord chaining:

```ruby
Product.search(:description).matching_all("running")
       .search(:category).term("footwear")
       .where(in_stock: true)
       .order(:id)
       .limit(10)
```

### Method Name Conflicts

This gem defines a model class method named `.search`.
If your application already defines `.search`, rails-paradedb will **not** override it.

Use `.paradedb_search` instead:

```ruby
Product.paradedb_search(:description).matching_all("shoes")
```

## Arel Layer

See the dedicated Arel guide: [`lib/parade_db/arel/README.md`](lib/parade_db/arel/README.md).

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

## Support

If you're missing a feature or have found a bug, please open a
[GitHub Issue](https://github.com/paradedb/rails-paradedb/issues/new/choose).

To get community support, you can:

- Post a question in the [ParadeDB Slack Community](https://join.slack.com/t/paradedbcommunity/shared_invite/zt-32abtyjg4-yoYoi~RPh9MSW8tDbl0BQw)
- Ask for help on our [GitHub Discussions](https://github.com/paradedb/paradedb/discussions)

If you need commercial support, please [contact the ParadeDB team](mailto:sales@paradedb.com).

## License

rails-paradedb is licensed under the [MIT License](LICENSE).
