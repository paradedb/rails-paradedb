#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

VERSION="$(ruby -e 'require File.expand_path("lib/parade_db/version", Dir.pwd); print ParadeDB::VERSION')"
GEM_FILE="rails-paradedb-${VERSION}.gem"

rm -f "${GEM_FILE}"
gem build rails-paradedb.gemspec >/dev/null

if [[ ! -f "${GEM_FILE}" ]]; then
  echo "❌ Expected gem file not found after build: ${GEM_FILE}" >&2
  exit 1
fi

SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rails-paradedb-smoke.XXXXXX")"
GEM_HOME_DIR="${SMOKE_DIR}/gem-home"
HOME_DIR="${SMOKE_DIR}/home"

cleanup() {
  rm -rf "${SMOKE_DIR}" "${GEM_FILE}"
}
trap cleanup EXIT

mkdir -p "${GEM_HOME_DIR}" "${HOME_DIR}"
export HOME="${HOME_DIR}"
export GEM_SPEC_CACHE="${SMOKE_DIR}/spec-cache"

gem install --no-document --install-dir "${GEM_HOME_DIR}" "${GEM_FILE}" >/dev/null

EXPECTED_VERSION="${VERSION}" GEM_HOME="${GEM_HOME_DIR}" GEM_PATH="${GEM_HOME_DIR}" ruby <<'RUBY'
require "parade_db"

expected = ENV.fetch("EXPECTED_VERSION")
abort("Version mismatch: expected #{expected}, got #{ParadeDB::VERSION}") unless ParadeDB::VERSION == expected
abort("ParadeDB::Arel should not be public") if ParadeDB.const_defined?(:Arel, false)
abort("Search modifier construction failed") unless ParadeDB.boost("running shoes", 2)

puts "✅ Package smoke install passed for rails-paradedb #{ParadeDB::VERSION}"
RUBY
