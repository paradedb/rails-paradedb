#!/usr/bin/env bash

set -euo pipefail

# Pure Ruby/unit tests (no ParadeDB container needed)
if [[ $# -gt 0 ]]; then
  bundle exec ruby -Ilib -Ispec "$@"
else
  bundle exec ruby -Ilib -Ispec -e 'Dir["spec/**/*_unit_spec.rb"].sort.each { |f| require File.expand_path(f) }'
fi
