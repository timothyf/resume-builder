#!/bin/bash

set -euo pipefail

resolve_bundle_bin() {
  if [ -n "${BUNDLE_BIN:-}" ]; then
    if [ -x "$BUNDLE_BIN" ]; then
      echo "$BUNDLE_BIN"
      return 0
    fi

    echo "BUNDLE_BIN is set but not executable: $BUNDLE_BIN" >&2
    exit 1
  fi

  if command -v bundle >/dev/null 2>&1; then
    command -v bundle
    return 0
  fi

  echo "Could not find 'bundle' in PATH. Install Bundler or set BUNDLE_BIN to an executable path." >&2
  exit 1
}

bundle_bin="$(resolve_bundle_bin)"
exec "$bundle_bin" "$@"