#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for test_file in "$SCRIPT_DIR"/*_test.bash; do
  echo "Running $(basename "$test_file")"
  "$test_file"
  echo
 done

echo "Shell test suite completed"
