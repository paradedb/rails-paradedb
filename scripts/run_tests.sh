#!/usr/bin/env bash
#
# run_tests.sh
#
# Runs the full test suite. Pass a spec file to narrow it; it is forwarded to
# the integration run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/run_unit_tests.sh"
bash "${SCRIPT_DIR}/run_integration_tests.sh" "$@"
