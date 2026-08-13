#!/bin/bash

set -euo pipefail

export THOR_SILENCE_DEPRECATION=1
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/scripts/resume_selection_args.bash"

usage_text="Usage: ./build_resume.bash [--resume-user USER] [--resume-name NAME] [--theme THEME]"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "$usage_text"
  exit 0
fi

parse_resume_selection_args "$usage_text" "$@"

"$script_dir/scripts/run_bundle.bash" exec middleman build
