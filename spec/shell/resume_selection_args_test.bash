#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/resume_selection_args.bash"

failures=0

run_test() {
  local name="$1"
  shift

  if "$@"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    failures=$((failures + 1))
  fi
}

test_sets_env_from_cli_args() {
  (
    unset ACTIVE_RESUME_USER ACTIVE_RESUME_NAME
    parse_resume_selection_args "usage" --resume-user alice --resume-name resume_a
    [[ "${ACTIVE_RESUME_USER:-}" == "alice" ]]
    [[ "${ACTIVE_RESUME_NAME:-}" == "resume_a" ]]
  )
}

test_uses_existing_env_when_no_args() {
  (
    export ACTIVE_RESUME_USER="bob"
    export ACTIVE_RESUME_NAME="resume_b"
    parse_resume_selection_args "usage"
    [[ "${ACTIVE_RESUME_USER:-}" == "bob" ]]
    [[ "${ACTIVE_RESUME_NAME:-}" == "resume_b" ]]
  )
}

test_missing_resume_user_value_fails() {
  (
    unset ACTIVE_RESUME_USER ACTIVE_RESUME_NAME
    set +e
    output="$(parse_resume_selection_args "usage" --resume-user 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]]
    [[ "$output" == *"Missing value for --resume-user"* ]]
  )
}

test_missing_resume_name_value_fails() {
  (
    unset ACTIVE_RESUME_USER ACTIVE_RESUME_NAME
    set +e
    output="$(parse_resume_selection_args "usage" --resume-name 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]]
    [[ "$output" == *"Missing value for --resume-name"* ]]
  )
}

test_unknown_option_fails() {
  (
    unset ACTIVE_RESUME_USER ACTIVE_RESUME_NAME
    set +e
    output="$(parse_resume_selection_args "usage" --bogus 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]]
    [[ "$output" == *"Unknown option: --bogus"* ]]
  )
}

run_test "sets env from CLI args" test_sets_env_from_cli_args
run_test "uses existing env with no args" test_uses_existing_env_when_no_args
run_test "missing --resume-user value fails" test_missing_resume_user_value_fails
run_test "missing --resume-name value fails" test_missing_resume_name_value_fails
run_test "unknown option fails" test_unknown_option_fails

if [[ $failures -gt 0 ]]; then
  echo "Shell tests failed: $failures"
  exit 1
fi

echo "All shell tests passed"
