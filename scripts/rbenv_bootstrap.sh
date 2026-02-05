#!/usr/bin/env bash

set -euo pipefail

RUBY_VERSION="4.0.0"
BUNDLER_VERSION="4.0.3"

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
