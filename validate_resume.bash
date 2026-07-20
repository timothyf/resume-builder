#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/scripts/resume_selection_args.bash"

parse_resume_selection_args "Usage: ./validate_resume.bash [--resume-user USER] [--resume-name NAME] [--theme THEME]" "$@"

"$script_dir/scripts/run_bundle.bash" exec ruby "$script_dir/scripts/validate_resume.rb"
