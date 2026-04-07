#!/bin/bash

set -euo pipefail

export THOR_SILENCE_DEPRECATION=1
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resume_user="${ACTIVE_RESUME_USER:-}"
resume_name="${ACTIVE_RESUME_NAME:-}"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--resume-user)
			resume_user="${2:-}"
			shift 2
			;;
		--resume-name)
			resume_name="${2:-}"
			shift 2
			;;
		*)
			echo "Unknown option: $1" >&2
			echo "Usage: ./deploy_resume.bash [--resume-user USER] [--resume-name NAME]" >&2
			exit 1
			;;
	esac
done

if [[ -n "$resume_user" ]]; then
	export ACTIVE_RESUME_USER="$resume_user"
fi

if [[ -n "$resume_name" ]]; then
	export ACTIVE_RESUME_NAME="$resume_name"
fi

"$script_dir/scripts/run_bundle.bash" exec middleman deploy
 
