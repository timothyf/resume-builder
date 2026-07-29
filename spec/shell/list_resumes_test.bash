#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/scripts/list_resumes.rb"

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

test_lists_legacy_and_structured_resumes() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  mkdir -p "$tmp_dir/data/person/resumes/resume_structured"
  cat > "$tmp_dir/data/active_resume.yml" <<'YAML'
user: person
name: resume_current
YAML
  cat > "$tmp_dir/data/person/resume_legacy.yml" <<'YAML'
---
YAML
  cat > "$tmp_dir/data/person/resumes/resume_structured/resume.yml" <<'YAML'
---
YAML

  set +e
  output="$(RESUME_PROJECT_ROOT="$tmp_dir" ruby "$SCRIPT_PATH" --user person 2>&1)"
  status=$?
  set -e

  [[ $status -eq 0 ]] || return 1
  [[ "$output" == *"resume_legacy [legacy]"* ]] || return 1
  [[ "$output" == *"resume_structured [structured]"* ]] || return 1

  rm -rf "$tmp_dir"
}

test_rejects_invalid_format() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  mkdir -p "$tmp_dir/data/person"
  cat > "$tmp_dir/data/active_resume.yml" <<'YAML'
user: person
name: resume_current
YAML

  set +e
  output="$(RESUME_PROJECT_ROOT="$tmp_dir" ruby "$SCRIPT_PATH" --user person --format yaml 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || return 1
  [[ "$output" == *"Invalid --format value"* ]] || return 1

  rm -rf "$tmp_dir"
}

run_test "lists legacy and structured resumes" test_lists_legacy_and_structured_resumes
run_test "rejects invalid format" test_rejects_invalid_format

if [[ $failures -gt 0 ]]; then
  echo "Shell tests failed: $failures"
  exit 1
fi

echo "All shell tests passed"
