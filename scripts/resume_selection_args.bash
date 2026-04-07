#!/bin/bash

parse_resume_selection_args() {
  local usage_text="$1"
  shift

  local resume_user="${ACTIVE_RESUME_USER:-}"
  local resume_name="${ACTIVE_RESUME_NAME:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --resume-user)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "Missing value for --resume-user" >&2
          echo "$usage_text" >&2
          return 1
        fi
        resume_user="$2"
        shift 2
        ;;
      --resume-name)
        if [[ $# -lt 2 || -z "${2:-}" ]]; then
          echo "Missing value for --resume-name" >&2
          echo "$usage_text" >&2
          return 1
        fi
        resume_name="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        echo "$usage_text" >&2
        return 1
        ;;
    esac
  done

  if [[ -n "$resume_user" ]]; then
    export ACTIVE_RESUME_USER="$resume_user"
  fi

  if [[ -n "$resume_name" ]]; then
    export ACTIVE_RESUME_NAME="$resume_name"
  fi
}