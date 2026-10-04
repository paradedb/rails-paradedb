#!/usr/bin/env bash
#
# run_tests.sh
#
# Runs the test suite. Pass a spec file to narrow it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# Optional Rails version: --rails 7.2 | --rails 8.1  (or RAILS_VERSION env var)
if [[ "${1:-}" == "--rails" ]]; then
  RAILS_VERSION="${2:?'--rails requires a version argument (e.g. 7.2 or 8.1)'}"
  shift 2
fi

case "${RAILS_VERSION:-8.1}" in
  7.2) export BUNDLE_GEMFILE="${REPO_ROOT}/gemfiles/rails72.gemfile" ;;
  8.1) export BUNDLE_GEMFILE="${REPO_ROOT}/Gemfile" ;;
  *)
    echo "Unsupported Rails version: ${RAILS_VERSION}. Supported: 7.2, 8.1" >&2
    exit 1
    ;;
esac

echo "==> Testing with Rails ${RAILS_VERSION:-8.1} (${BUNDLE_GEMFILE})"

# shellcheck source=scripts/rbenv_bootstrap.sh
source "${SCRIPT_DIR}/rbenv_bootstrap.sh"

if [[ -z "${PARADEDB_TEST_DSN:-${DATABASE_URL:-}}" ]]; then
  # shellcheck source=scripts/run_paradedb.sh
  source "${SCRIPT_DIR}/run_paradedb.sh"
fi

export PARADEDB_TEST_DSN="${PARADEDB_TEST_DSN:-${DATABASE_URL}}"
export DATABASE_URL="${DATABASE_URL:-${PARADEDB_TEST_DSN}}"
export PGPASSWORD="${PGPASSWORD:-${PARADEDB_PASSWORD:-postgres}}"

if [[ $# -gt 0 ]]; then
  bundle exec rspec "$@"
else
  bundle exec rspec spec
fi
