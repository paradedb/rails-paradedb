# ParadeDB for Rails: Examples

Runnable scripts for integrating ParadeDB search features into an ActiveRecord application.

## Getting Started

### 1. Install dependencies

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle install
```

### 2. Start ParadeDB

```bash
source scripts/run_paradedb.sh
```

This starts the local ParadeDB Docker container and exports `DATABASE_URL`.

### 3. Run examples

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/quickstart/quickstart.rb
```

## Examples

### Core Examples

1. Quickstart (`quickstart/quickstart.rb`)

Shows keyword search, score ordering, phrase matching, snippet generation,
and standard ActiveRecord filtering.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/quickstart/quickstart.rb
```

1. Faceted Search (`faceted_search/faceted_search.rb`)

Returns top-N rows with facet aggregations in one query flow.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/faceted_search/faceted_search.rb
```

### Advanced Examples

1. Autocomplete (`autocomplete/`)

Creates an ngram index and runs prefix-style queries.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/autocomplete/setup.rb
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/autocomplete/autocomplete.rb
```

1. More Like This (`more_like_this/more_like_this.rb`)

Runs similarity search based on document term statistics.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/more_like_this/more_like_this.rb
```

### Vector and RAG Examples

1. Hybrid Search with RRF (`hybrid_rrf/`)

Combines BM25 and vector ranking with Reciprocal Rank Fusion in a single SQL
query using CTEs.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/hybrid_rrf/setup.rb
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/hybrid_rrf/hybrid_rrf.rb
```

1. RAG (`rag/rag.rb`)

Retrieves product rows with ParadeDB and sends context to OpenRouter.

```bash
export OPENROUTER_API_KEY=sk-...
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/rag/rag.rb
```

## Shared Helpers

`examples/common.rb` provides:

- ActiveRecord connection bootstrap
- `MockItem` model using `ParadeDB::Model`
- `setup_mock_items!` to create the table + BM25 index via
  `ParadeDB::Index` DSL (`MockItemIndex`)
