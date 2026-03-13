# rails-paradedb

[![Gem Version](https://img.shields.io/gem/v/rails-paradedb)](https://rubygems.org/gems/rails-paradedb)
[![CI](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml/badge.svg)](https://github.com/paradedb/rails-paradedb/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/paradedb/rails-paradedb?color=blue)](https://github.com/paradedb/rails-paradedb?tab=MIT-1-ov-file#readme)

ActiveRecord integration for [ParadeDB](https://paradedb.com): BM25 full-text search, scoring, snippets, facets, and aggregations in PostgreSQL.

ParadeDB docs: <https://docs.paradedb.com>

## Requirements

- Ruby 3.2+
- Rails 7.2+
- PostgreSQL 17+ with `pg_search` (ParadeDB)

## Installation

```ruby
gem "rails-paradedb"
```

```bash
bundle install
```

## Quick Start

```ruby
class MockItem < ActiveRecord::Base
  include ParadeDB::Model

  self.table_name = "mock_items"
  self.primary_key = "id"
  self.has_paradedb_index = true
end
```

```ruby
MockItem.search(:description).matching_all("running shoes")
MockItem.search(:description).matching_any("wireless", "bluetooth")
MockItem.search(:description).term("electronics")
```

## Index Definition

```ruby
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

For text or JSON fields you plan to use in Top K queries, facets, grouped
aggregations, or `top_hits` docvalue fields, use `:literal` or
`:literal_normalized`.

Create in migration:

```ruby
class AddMockItemBm25Index < ActiveRecord::Migration[8.1]
  def up
    create_paradedb_index(MockItemIndex, if_not_exists: true)
  end

  def down
    remove_bm25_index :mock_items, name: :search_idx, if_exists: true
  end
end
```

## Query API

```ruby
# Full-text
MockItem.search(:description).matching_all("running shoes")
MockItem.search(:description).matching_any("wireless bluetooth")

# Query-time tokenizer override
MockItem.search(:description).matching_any("running shoes", tokenizer: "whitespace")
MockItem.search(:description).matching_any("running shoes", tokenizer: "whitespace('lowercase=false')")

# Fuzzy options on match/term
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
MockItem.search(:description).near(ParadeDB.regex("run.*"), anchor: "shoes", distance: 3)
MockItem.search(:description).near("running", "trail", anchor: "shoes", distance: 3)
MockItem.search(:description).near(ParadeDB.regex("run.*"), "trail", anchor: "shoes", distance: 3)
MockItem.search(:description).regex_phrase("run.*", "shoes")
MockItem.search(:description).phrase_prefix("run", "sh")
MockItem.search(:description).phrase_prefix("run", "sh", max_expansion: 100)
MockItem.search(:description).parse("running AND shoes", lenient: true)
MockItem.search(:description).parse("running shoes", conjunction_mode: true)

MockItem.search(:id).match_all
MockItem.search(:id).exists
MockItem.search(:rating).range(gte: 3, lt: 5)
MockItem.search(:weight_range).range_term("(10, 12]", relation: "Intersects")

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

# Non-exact window facets
relation = MockItem.search(:description)
                  .matching_all("shoes")
                  .with_facets(:category, size: 10, exact: false)
                  .order(:id)
                  .limit(10)

# Facets-only aggregate
MockItem.search(:description).matching_all("shoes").facets(:category)

# Named aggregations
MockItem.search(:description).matching_all("shoes").facets_agg(
  docs: ParadeDB::Aggregations.value_count(:id),
  avg_rating: ParadeDB::Aggregations.avg(:rating)
)

# Non-exact window named aggregations
MockItem.search(:description).matching_all("shoes").with_agg(
  exact: false,
  docs: ParadeDB::Aggregations.value_count(:id)
).order(:id).limit(10)
```

## Diagnostics Helpers

Ruby helpers:

```ruby
ParadeDB.paradedb_indexes
ParadeDB.paradedb_index_segments("search_idx")
ParadeDB.paradedb_verify_index("search_idx", sample_rate: 0.1)
ParadeDB.paradedb_verify_all_indexes(index_pattern: "search_idx")
```

Rake tasks:

```bash
rake paradedb:diagnostics:indexes
rake "paradedb:diagnostics:index_segments[search_idx]"
rake "paradedb:diagnostics:verify_index[search_idx]" SAMPLE_RATE=0.1
rake paradedb:diagnostics:verify_all_indexes INDEX_PATTERN=search_idx
```

Note: availability depends on your installed `pg_search` version.

## Examples

- [Quick Start](examples/quickstart/quickstart.rb)
- [Faceted Search](examples/faceted_search/faceted_search.rb)
- [Autocomplete](examples/autocomplete/autocomplete.rb)
- [More Like This](examples/more_like_this/more_like_this.rb)
- [Hybrid RRF](examples/hybrid_rrf/hybrid_rrf.rb)
- [RAG](examples/rag/rag.rb)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT
