#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/scripts/run_bundle.bash" exec ruby "$script_dir/scripts/validate_supported_resumes.rb"
