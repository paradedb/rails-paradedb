# Examples

Self-contained scripts that show how to use ParadeDB from ActiveRecord. Run them all with `scripts/run_examples.sh`, or follow the setup below and run them one at a time.

Each example folder uses a Rails-like layout: `model.rb` for the ActiveRecord model, `setup.rb` for the connection and table/index setup, and a main script for the demo flow.

## Getting Started

### 1. Install dependencies

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle install
```

### 2. Start ParadeDB

```bash
source scripts/run_paradedb.sh
```

This starts a ParadeDB container via Docker and exports `DATABASE_URL`. If you already have a Postgres instance with ParadeDB installed, set `DATABASE_URL` yourself instead:

```bash
export DATABASE_URL=postgresql://user:password@localhost:5432/dbname
```

## Quickstart (`quickstart/quickstart.rb`)

The "Hello World" of ParadeDB. Covers keyword search, score ordering, phrase matching, snippets and highlighting, and combining search with ActiveRecord filters.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/quickstart/quickstart.rb
```

## Vector Search (`vector_search/vector_search.rb`)

Top-K nearest-neighbor retrieval over pgvector `vector(n)` columns, using metric opclasses and `nearest` queries. ParadeDB indexes the vector column inside its search index, so one index serves both keyword and vector queries.

Requires the `pgvector` extension, which is included in the ParadeDB Docker image.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/vector_search/setup.rb
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/vector_search/vector_search.rb
```

## Faceted Search (`faceted_search/faceted_search.rb`)

Builds an e-commerce-style filter sidebar. Computes the top K rows and facet buckets together in a single flow.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/faceted_search/faceted_search.rb
```

## Hybrid Search (RRF) (`hybrid_rrf/hybrid_rrf.rb`)

Combines BM25 keyword search (good for exact matches like part numbers) with vector similarity (good for meaning) using Reciprocal Rank Fusion. Composes a ParadeDB BM25 relation with a semantic relation via CTEs, using the native vector distance helpers.

Requires the `pgvector` extension, which is included in the ParadeDB Docker image.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/hybrid_rrf/setup.rb
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/hybrid_rrf/hybrid_rrf.rb
```

## RAG (`rag/rag.rb`)

A small question-answering flow. Retrieves products by combining full-text search with `nearest` vector retrieval, then sends the context to an LLM so answers are grounded in your own data.

Requires an [OpenRouter](https://openrouter.ai/) API key:

```bash
export OPENROUTER_API_KEY=sk-...
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/rag/rag.rb
```

## Autocomplete (`autocomplete/autocomplete.rb`)

As-you-type suggestions using n-gram tokenization, which matches substrings in the middle of words — typing `wir` matches `wireless`.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/autocomplete/setup.rb
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/autocomplete/autocomplete.rb
```

## More Like This (`more_like_this/more_like_this.rb`)

"Related content" recommendations. Finds documents with similar keywords using TF-IDF logic, without requiring vector embeddings.

```bash
BUNDLE_GEMFILE=examples/Gemfile bundle exec ruby examples/more_like_this/more_like_this.rb
```
