#!/usr/bin/env bash
#
# run_examples.sh
#
# Runs every example against a local ParadeDB instance. Starts the container via
# scripts/run_paradedb.sh unless DATABASE_URL is already set.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ -z "${DATABASE_URL:-}" ]]; then
  # shellcheck source=/dev/null
  source scripts/run_paradedb.sh
fi

export BUNDLE_GEMFILE="${ROOT}/examples/Gemfile"

examples=(
  "quickstart/quickstart.rb"
  "vector_search/setup.rb"
  "vector_search/vector_search.rb"
  "faceted_search/faceted_search.rb"
  "hybrid_rrf/setup.rb"
  "hybrid_rrf/hybrid_rrf.rb"
)

if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
  examples+=("rag/rag.rb")
else
  echo "OPENROUTER_API_KEY is not set, skipping the RAG example." >&2
fi

examples+=(
  "autocomplete/setup.rb"
  "autocomplete/autocomplete.rb"
  "more_like_this/more_like_this.rb"
)

for example in "${examples[@]}"; do
  echo
  echo "==> Running ${example}"
  bundle exec ruby "examples/${example}"
done
