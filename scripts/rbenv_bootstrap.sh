#!/usr/bin/env bash

set -euo pipefail

RUBY_VERSION="4.0.0"
BUNDLER_VERSION="4.0.3"

# Skip rbenv setup if Ruby 4.0+ is already available (e.g., in CI)
if command -v ruby >/dev/null 2>&1 && ruby --version | grep -qE "ruby 4\.(0|1)"; then
  CURRENT_RUBY=$(ruby --version | grep -oE "ruby [0-9]+\.[0-9]+\.[0-9]+" | cut -d' ' -f2)
  echo "Ruby ${CURRENT_RUBY} already available, skipping rbenv setup"
  if ! gem list -i "bundler" -v "${BUNDLER_VERSION}" >/dev/null 2>&1; then
    gem install "bundler:${BUNDLER_VERSION}"
  fi
  bundle install >/dev/null
  exit 0
fi

if ! command -v rbenv >/dev/null 2>&1; then
  echo "rbenv is not installed. Install rbenv and retry." >&2
  exit 1
fi

eval "$(rbenv init -)"

if ! rbenv versions --bare | grep -qx "${RUBY_VERSION}"; then
  rbenv install "${RUBY_VERSION}"
fi

rbenv local "${RUBY_VERSION}"

if ! rbenv exec gem list -i "bundler" -v "${BUNDLER_VERSION}" >/dev/null 2>&1; then
  rbenv exec gem install "bundler:${BUNDLER_VERSION}"
  rbenv rehash
fi

rbenv exec bundle install >/dev/null
