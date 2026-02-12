# ParadeDB for Rails: Examples & Cookbook

Welcome to the **ParadeDB for Rails** examples. This directory contains
self-contained scripts that show how to integrate ParadeDB search features into
your Ruby on Rails / ActiveRecord application.

Each example folder uses a Rails-like layout:

- `model.rb` for ActiveRecord model definitions
- `setup.rb` for connection/bootstrap and table/index setup
- a main script for the demo flow

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

Structure:

- `examples/quickstart/model.rb`
- `examples/quickstart/setup.rb`
- `examples/quickstart/quickstart.rb`

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
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/quickstart/quickstart.rb
```

1. Faceted Search (`faceted_search/faceted_search.rb`)

Top-N rows plus facet buckets in one flow.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/faceted_search/faceted_search.rb
```

Structure:

- `examples/faceted_search/model.rb`
- `examples/faceted_search/setup.rb`
- `examples/faceted_search/faceted_search.rb`

### Smart Features

1. Autocomplete (`autocomplete/`)

Creates an ngram index and runs as-you-type queries.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/autocomplete/setup.rb
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/autocomplete/autocomplete.rb
```

Structure:

- `examples/autocomplete/model.rb`
- `examples/autocomplete/setup.rb`
- `examples/autocomplete/autocomplete.rb`

1. More Like This (`more_like_this/more_like_this.rb`)

Recommendation-style search based on document similarity.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/more_like_this/more_like_this.rb
```

Structure:

- `examples/more_like_this/model.rb`
- `examples/more_like_this/setup.rb`
- `examples/more_like_this/more_like_this.rb`

### AI & Vectors

1. Hybrid Search with RRF (`hybrid_rrf/`)

Combines BM25 + vector ranking with Reciprocal Rank Fusion in a single SQL query
using CTEs, built from ParadeDB and neighbor ActiveRecord relations.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/hybrid_rrf/setup.rb
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/hybrid_rrf/hybrid_rrf.rb
```

Structure:

- `examples/hybrid_rrf/model.rb`
- `examples/hybrid_rrf/setup.rb`
- `examples/hybrid_rrf/hybrid_rrf.rb`

1. RAG (`rag/rag.rb`)

Retrieves products with ParadeDB and sends context to OpenRouter.

```bash
export OPENROUTER_API_KEY=sk-...
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/rag/rag.rb
```

Structure:

- `examples/rag/model.rb`
- `examples/rag/setup.rb`
- `examples/rag/rag.rb`
