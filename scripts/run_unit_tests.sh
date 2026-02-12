#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/rbenv_bootstrap.sh"

# Unit tests run against PostgreSQL only.
# Mirror integration script defaults so both suites share adapter/runtime behavior.
if [[ -z "${CI:-}" ]]; then
  source "${SCRIPT_DIR}/run_paradedb.sh"
fi

PORT="${PARADEDB_PORT:-5432}"
USER="${PARADEDB_USER:-postgres}"
PASSWORD="${PARADEDB_PASSWORD:-postgres}"
DB="${PARADEDB_DB:-postgres}"

export PARADEDB_TEST_DSN="postgres://${USER}:${PASSWORD}@localhost:${PORT}/${DB}"
export PGPASSWORD="${PASSWORD}"

if [[ $# -gt 0 ]]; then
  bundle exec rspec "$@"
else
  bundle exec rspec spec --pattern '**/*_unit_spec.rb'
fi
