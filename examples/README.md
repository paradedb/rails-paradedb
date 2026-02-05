# ParadeDB for Rails: Examples & Cookbook

This directory mirrors the Django examples and shows how to use ParadeDB from
Ruby/ActiveRecord with the `rails-paradedb` DSL.

## Getting Started

### 1. Install dependencies

```bash
bundle install
```

### 2. Start ParadeDB

```bash
source scripts/run_paradedb.sh
```

This starts the local ParadeDB Docker container and exports `DATABASE_URL`.

### 3. Run examples

```bash
bundle exec ruby examples/quickstart/quickstart.rb
```

## Examples

### Essentials

1. Quickstart (`quickstart/quickstart.rb`)

Core search operations:
- keyword search
- score ordering
- phrase matching
- snippets/highlighting
- search + ActiveRecord filters

```bash
bundle exec ruby examples/quickstart/quickstart.rb
```

2. Faceted Search (`faceted_search/faceted_search.rb`)

Top-N rows plus facet buckets in one flow.

```bash
bundle exec ruby examples/faceted_search/faceted_search.rb
```

### Smart Features

3. Autocomplete (`autocomplete/`)

Creates an ngram index and runs as-you-type queries.

```bash
bundle exec ruby examples/autocomplete/setup.rb
bundle exec ruby examples/autocomplete/autocomplete.rb
```

4. More Like This (`more_like_this/more_like_this.rb`)

Recommendation-style search based on document similarity.

```bash
bundle exec ruby examples/more_like_this/more_like_this.rb
```

### AI & Vectors

5. Hybrid Search with RRF (`hybrid_rrf/`)

Combines BM25 + vector ranking with Reciprocal Rank Fusion.

```bash
bundle exec ruby examples/hybrid_rrf/setup.rb
bundle exec ruby examples/hybrid_rrf/hybrid_rrf.rb
```

6. RAG (`rag/rag.rb`)

Retrieves products with ParadeDB and sends context to OpenRouter.

```bash
export OPENROUTER_API_KEY=sk-...
bundle exec ruby examples/rag/rag.rb
```

## Shared Helpers

`examples/common.rb` provides:
- ActiveRecord connection bootstrap
- `MockItem` model using `ParadeDB::Model`
- `setup_mock_items!` to create the table + BM25 index
