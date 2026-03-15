<!-- ParadeDB: Postgres for Search and Analytics -->
<h1 align="center">
  <a href="https://paradedb.com"><img src="https://github.com/paradedb/paradedb/raw/main/docs/logo/readme.svg" alt="ParadeDB"></a>
<br>
</h1>

<p align="center">
  <b>Simple, Elastic-quality search for Postgres</b><br/>
</p>

<h3 align="center">
  <a href="https://paradedb.com">Website</a> &bull;
  <a href="https://docs.paradedb.com">Docs</a> &bull;
  <a href="https://paradedb.com/slack/">Community</a> &bull;
  <a href="https://paradedb.com/blog/">Blog</a> &bull;
  <a href="https://docs.paradedb.com/changelog/">Changelog</a>
</h3>

---

# rails-paradedb

[![Gem Version](https://img.shields.io/gem/v/rails-paradedb)](https://rubygems.org/gems/rails-paradedb)
[![Ruby Requirement](https://img.shields.io/gem/rd/rails-paradedb)](https://rubygems.org/gems/rails-paradedb)
[![Gem Downloads](https://img.shields.io/gem/dt/rails-paradedb)](https://rubygems.org/gems/rails-paradedb)
[![CI](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml/badge.svg)](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/paradedb/rails-paradedb/graph/badge.svg)](https://codecov.io/gh/paradedb/rails-paradedb)
[![License](https://img.shields.io/github/license/paradedb/rails-paradedb?color=blue)](https://github.com/paradedb/rails-paradedb?tab=MIT-1-ov-file#readme)
[![Slack URL](https://img.shields.io/badge/Join%20Slack-purple?logo=slack&link=https%3A%2F%2Fparadedb.com%2Fslack)](https://paradedb.com/slack)
[![X URL](https://img.shields.io/twitter/url?url=https%3A%2F%2Ftwitter.com%2Fparadedb&label=Follow%20%40paradedb)](https://x.com/paradedb)

The official Ruby client for [ParadeDB](https://paradedb.com), built for ActiveRecord.
Use Elastic-quality full-text search, scoring, snippets, facets, and aggregations directly from Rails.

## Features

- BM25 index management in Rails migrations (`create_paradedb_index`, `remove_bm25_index`, `reindex_bm25`)
- Chainable ActiveRecord search API (`matching_all`, `matching_any`, `term`, `phrase`, `regex`, `near`, `parse`, and more)
- Relevance and highlighting (`with_score`, `with_snippet`, `with_snippets`, `with_snippet_positions`)
- Facets and aggregations (`with_facets`, `facets`, `with_agg`, `facets_agg`, `aggregate_by`)
- More Like This similarity search (`more_like_this`)
- Arel integration for advanced query composition with native ParadeDB operators
- Diagnostics helpers and rake tasks for index health and verification
- Optional runtime index validation to detect missing/drifted BM25 indexes

## Requirements & Compatibility

| Component  | Supported                                    |
| ---------- | -------------------------------------------- |
| Ruby       | 3.2+                                         |
| Rails      | 7.2+                                         |
| PostgreSQL | PostgreSQL adapter only                      |
| ParadeDB   | `pg_search` installed in your target database |

Notes:

- CI runs Ruby `3.2` through `4.0` across Rails `7.2` and `8.1`.
- Schema compatibility is checked against every ParadeDB release.

## Installation

```ruby
gem "rails-paradedb"
```

```bash
bundle install
```

## Quick Start

### Prerequisites

Make sure your Rails app uses PostgreSQL and that `pg_search` is installed in the target database:

```sql
CREATE EXTENSION IF NOT EXISTS pg_search;
```

### 1. Define Your Model and Index

```ruby
class MockItem < ActiveRecord::Base
  include ParadeDB::Model

  self.table_name = "mock_items"
  self.primary_key = "id"
  self.has_paradedb_index = true
end

class MockItemIndex < ParadeDB::Index
  self.table_name = :mock_items
  self.key_field = :id
  self.index_name = :search_idx
  self.fields = {
    id: nil,
    description: nil,
    category: nil,
    rating: nil,
    in_stock: nil,
    created_at: nil,
    metadata: nil,
    weight_range: nil
  }
end
```

### 2. Create the BM25 Index in a Migration

```ruby
class AddMockItemBm25Index < ActiveRecord::Migration[7.2] # use your app's migration version
  def up
    create_paradedb_index(MockItemIndex, if_not_exists: true)
  end

  def down
    remove_bm25_index :mock_items, name: :search_idx, if_exists: true
  end
end
```

### 3. Search

```ruby
MockItem.search(:description).matching_all("running shoes")
MockItem.search(:description).matching_any("wireless", "bluetooth")
MockItem.search(:description).term("electronics")
```

## Query API

```ruby
# Full text
MockItem.search(:description).matching_all("running shoes")
MockItem.search(:description).matching_any("wireless bluetooth")

# Query-time tokenizer override
MockItem.search(:description).matching_any("running shoes", tokenizer: "whitespace")
MockItem.search(:description).matching_any("running shoes", tokenizer: "whitespace('lowercase=false')")

# Fuzzy options
MockItem.search(:description).matching_any("runing shose", distance: 1)
MockItem.search(:description).matching_all("runing", distance: 1, prefix: true)
MockItem.search(:description).term("shose", distance: 1, transposition_cost_one: true)

# Other query types
MockItem.search(:description).phrase("running shoes", slop: 2)
MockItem.search(:description).phrase("running shoes", tokenizer: "whitespace")
MockItem.search(:description).phrase(%w[running shoes])
MockItem.search(:description).regex("run.*")
MockItem.search(:description).near("running", anchor: "shoes", distance: 3)
MockItem.search(:description).near("running", anchor: "shoes", distance: 3, ordered: true)
MockItem.search(:description).near(ParadeDB.regex_term("run.*"), anchor: "shoes", distance: 3)
MockItem.search(:description).regex_phrase("run.*", "shoes")
MockItem.search(:description).phrase_prefix("run", "sh", max_expansion: 100)
MockItem.search(:description).parse("running AND shoes", lenient: true)

# Match-all / exists / ranges
MockItem.search(:id).match_all
MockItem.search(:id).exists
MockItem.search(:rating).range(gte: 3, lt: 5)
MockItem.search(:weight_range).range_term("(10, 12]", relation: "Intersects")

# Similarity
MockItem.more_like_this(42, fields: [:description])
```

## Scoring and Highlighting

```ruby
results = MockItem.search(:description)
                 .matching_all("shoes")
                 .with_score
                 .order(search_score: :desc)

MockItem.search(:description)
       .matching_all("shoes")
       .with_snippet(:description, start_tag: "<b>", end_tag: "</b>", max_chars: 80)

MockItem.search(:description)
       .matching_all("running")
       .with_snippets(:description, max_chars: 15, limit: 2, offset: 0, sort_by: :position)

MockItem.search(:description)
       .matching_all("running")
       .with_snippet_positions(:description)
```

## Facets and Aggregations

```ruby
# Rows + facets (requires order + limit)
relation = MockItem.search(:description)
                  .matching_all("shoes")
                  .with_facets(:category, size: 10)
                  .order(:id)
                  .limit(10)

rows = relation.to_a
facets = relation.facets

# Facets-only aggregate
MockItem.search(:description).matching_all("shoes").facets(:category)

# Named aggregations
MockItem.search(:description).matching_all("shoes").facets_agg(
  docs: ParadeDB::Aggregations.value_count(:id),
  avg_rating: ParadeDB::Aggregations.avg(:rating)
)

# Window aggregations + rows
MockItem.search(:description).matching_all("shoes").with_agg(
  exact: false,
  docs: ParadeDB::Aggregations.value_count(:id),
  stats: ParadeDB::Aggregations.stats(:rating)
).order(:id).limit(10)

# Grouped aggregations
MockItem.search(:id).match_all.aggregate_by(
  :category,
  docs: ParadeDB::Aggregations.value_count(:id)
)
```

If you group by text/JSON fields, index those fields using `:literal` or `:literal_normalized`.

## ActiveRecord and Arel Composition

Use ParadeDB conditions with normal ActiveRecord scopes:

```ruby
MockItem.search(:description)
        .matching_all("shoes")
        .where(in_stock: true)
        .where(MockItem.arel_table[:rating].gteq(4))
        .order(created_at: :desc)
```

For advanced SQL composition, ParadeDB operators are also available through Arel predications:

```ruby
t = MockItem.arel_table
MockItem.where(t[:description].pdb_match("running shoes"))
```

## Diagnostics Helpers

Ruby helpers:

```ruby
ParadeDB.paradedb_indexes
ParadeDB.paradedb_index_segments("search_idx")
ParadeDB.paradedb_verify_index("search_idx", sample_rate: 0.1)
ParadeDB.paradedb_verify_all_indexes(index_pattern: "search_idx")
```

Availability depends on the installed `pg_search` version.

Repository development tasks (from this repo's `Rakefile`):

```bash
rake paradedb:diagnostics:indexes
rake "paradedb:diagnostics:index_segments[search_idx]"
rake "paradedb:diagnostics:verify_index[search_idx]" SAMPLE_RATE=0.1
rake paradedb:diagnostics:verify_all_indexes INDEX_PATTERN=search_idx
```

## Index Validation

By default, index validation is disabled. You can enable runtime checks globally:

```ruby
# config/initializers/paradedb.rb
ParadeDB.index_validation_mode = :warn  # :warn, :raise, or :off
```

When enabled, `rails-paradedb` validates that the expected BM25 index exists and can raise
`ParadeDB::IndexDriftError` or `ParadeDB::IndexClassNotFoundError` depending on mode.

## Common Errors

### "No search field set. Call .search(column) first."

```ruby
# ❌ Missing .search(...)
MockItem.matching_all("shoes")

# ✅ Start with .search(column)
MockItem.search(:description).matching_all("shoes")
```

### "with_facets requires ORDER BY and LIMIT"

```ruby
# ❌ Missing order/limit
MockItem.search(:description).matching_all("shoes").with_facets(:category).to_a

# ✅ Include both
relation = MockItem.search(:description)
                   .matching_all("shoes")
                   .with_facets(:category)
                   .order(:id)
                   .limit(10)
relation.to_a
relation.facets
```

### "search(:field) is not indexed"

```ruby
# ❌ Field not in your ParadeDB::Index fields hash
MockItem.search(:title).matching_all("shoes")

# ✅ Add :title to the index definition, then migrate
```

## Security

`rails-paradedb` builds SQL through Arel nodes and quoted literals (`Arel::Nodes.build_quoted`)
rather than manual string interpolation. Tokenizer expressions are validated and search operators are
rendered through typed nodes, with unit and integration coverage for quoting and edge cases.

## Examples

- [Quick Start](examples/quickstart/quickstart.rb)
- [Faceted Search](examples/faceted_search/faceted_search.rb)
- [Autocomplete](examples/autocomplete/autocomplete.rb)
- [More Like This](examples/more_like_this/more_like_this.rb)
- [Hybrid RRF](examples/hybrid_rrf/hybrid_rrf.rb)
- [RAG](examples/rag/rag.rb)
- [Examples README](examples/README.md)

## Documentation

- **ParadeDB Official Docs**: <https://docs.paradedb.com>
- **ParadeDB Website**: <https://paradedb.com>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, test commands, linting, and PR workflow.

## Support

If you're missing a feature or found a bug, open a
[GitHub Issue](https://github.com/paradedb/rails-paradedb/issues/new/choose).

For community support:

- Join the [ParadeDB Slack Community](https://paradedb.com/slack)
- Ask in [ParadeDB Discussions](https://github.com/paradedb/paradedb/discussions)

For commercial support, contact [sales@paradedb.com](mailto:sales@paradedb.com).

## License

rails-paradedb is licensed under the [MIT License](LICENSE).
