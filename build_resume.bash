#!/bin/bash

set -euo pipefail

export THOR_SILENCE_DEPRECATION=1

bundle_bin="bundle"
if [ -x "$HOME/.rvm/wrappers/ruby-3.4.9@resume/bundle" ]; then
  bundle_bin="$HOME/.rvm/wrappers/ruby-3.4.9@resume/bundle"
fi

"$bundle_bin" exec middleman build
