#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Optional Rails version: --rails 7.2 | --rails 8.1  (or RAILS_VERSION env var)
if [[ "${1:-}" == "--rails" ]]; then
  RAILS_VERSION="${2:?'--rails requires a version argument (e.g. 7.2 or 8.1)'}"
  shift 2
fi

case "${RAILS_VERSION:-8.1}" in
  7.2) export BUNDLE_GEMFILE="${REPO_ROOT}/gemfiles/rails72.gemfile" ;;
  8.1) export BUNDLE_GEMFILE="${REPO_ROOT}/Gemfile" ;;
  *) echo "Unsupported Rails version: ${RAILS_VERSION}. Supported: 7.2, 8.1" >&2; exit 1 ;;
esac

echo "==> Testing with Rails ${RAILS_VERSION:-8.1} (${BUNDLE_GEMFILE})"

# shellcheck source=scripts/rbenv_bootstrap.sh
source "${SCRIPT_DIR}/rbenv_bootstrap.sh"

# Only start Docker container if not in CI (CI uses services)
if [[ -z "${CI:-}" ]]; then
  # shellcheck source=scripts/run_paradedb.sh
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
  bundle exec rspec spec --pattern '**/*_integration_spec.rb'
fi
