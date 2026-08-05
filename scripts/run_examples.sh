#!/usr/bin/env bash
#
# run_examples.sh
#
# Runs every example against a local ParadeDB instance and asserts that each one
# produced its expected output. Starts the container via scripts/run_paradedb.sh
# unless DATABASE_URL is already set.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ -z "${DATABASE_URL:-}" ]]; then
  # shellcheck source=/dev/null
  source scripts/run_paradedb.sh
fi

export BUNDLE_GEMFILE="${ROOT}/examples/Gemfile"

# Each entry is "<script>|<string the output must contain>". The assertion keeps
# a silently broken example from passing just because it exited 0.
examples=(
  "examples/quickstart/quickstart.rb|rails-paradedb Quickstart Example"
  "examples/vector_search/setup.rb|Vector Search Setup - Loading mock_items Table"
  "examples/vector_search/vector_search.rb|rails-paradedb Vector Search Example"
  "examples/faceted_search/faceted_search.rb|rails-paradedb Faceted Search Example"
  "examples/hybrid_rrf/setup.rb|Hybrid Search Setup"
  "examples/hybrid_rrf/hybrid_rrf.rb|Hybrid Search with Reciprocal Rank Fusion (single SQL query)"
  "examples/rag/rag.rb|RAG with rails-paradedb"
  "examples/autocomplete/setup.rb|Autocomplete Setup - Creating Dedicated Table"
  "examples/autocomplete/autocomplete.rb|rails-paradedb Autocomplete Example"
  "examples/more_like_this/more_like_this.rb|rails-paradedb MoreLikeThis Example"
)

for entry in "${examples[@]}"; do
  script="${entry%%|*}"
  expected="${entry##*|}"

  echo
  echo "==> Running ${script}"
  output="$(bundle exec ruby "${script}")"
  echo "${output}"

  if ! printf '%s' "${output}" | grep -F "${expected}" >/dev/null; then
    echo "Expected output not found in ${script}: ${expected}" >&2
    exit 1
  fi
done
