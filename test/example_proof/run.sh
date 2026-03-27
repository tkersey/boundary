#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
example_dir="$repo_root/examples"
fixture_dir="$repo_root/test/example_proof/fixtures"
cache_root="$(mktemp -d "${TMPDIR:-/tmp}/shift-example-proof-cache.XXXXXX")"
local_cache_dir="$cache_root/local"
global_cache_dir="$cache_root/global"

mkdir -p "$local_cache_dir" "$global_cache_dir"
trap 'rm -rf "$cache_root"' EXIT INT TERM

example_rows() {
  cat <<'EOF'
open_row_transform_basic.zig|primary|run-open-row-transform-basic|open_row_transform_basic.txt
open_row_choice_basic.zig|primary|run-open-row-choice-basic|open_row_choice_basic.txt
open_row_abort_basic.zig|primary|run-open-row-abort-basic|open_row_abort_basic.txt
open_row_workflow.zig|primary|run-open-row-workflow|open_row_workflow.txt
open_row_abortive_validation.zig|primary|run-open-row-abortive-validation|open_row_abortive_validation.txt
open_row_artifact_search.zig|primary|run-open-row-artifact-search|open_row_artifact_search.txt
open_row_generator.zig|primary|run-open-row-generator|open_row_generator.txt
open_row_state_writer.zig|primary|run-open-row-state-writer|open_row_state_writer.txt
EOF
}

check_primary_example() {
  example_path="$1"
  role="$2"

  if [ "$role" = "primary" ] && grep -q 'witnesses' "$example_path"; then
    echo "primary example must not depend on witnesses: $(basename "$example_path")" >&2
    exit 1
  fi
}

run_example() {
  example_name="$1"
  role="$2"
  step_name="$3"
  fixture_name="$4"
  example_path="$example_dir/$example_name"
  fixture_path="$fixture_dir/$fixture_name"
  stdout_file="$(mktemp)"

  if [ ! -f "$fixture_path" ]; then
    echo "missing fixture for $example_name: $fixture_name" >&2
    rm -f "$stdout_file"
    exit 1
  fi

  check_primary_example "$example_path" "$role"

  if ! zig build \
    "$step_name" \
    --cache-dir "$local_cache_dir" \
    --global-cache-dir "$global_cache_dir" \
    >"$stdout_file"
  then
    echo "example failed to run: $step_name" >&2
    rm -f "$stdout_file"
    exit 1
  fi

  if ! diff -u "$fixture_path" "$stdout_file" >/dev/null; then
    echo "example output mismatch for $step_name" >&2
    diff -u "$fixture_path" "$stdout_file" >&2 || true
    rm -f "$stdout_file"
    exit 1
  fi

  rm -f "$stdout_file"
  printf "%s\texact_output\n" "$step_name"
}

while IFS='|' read -r example_name role step_name fixture_name; do
  [ -n "$example_name" ] || continue
  run_example "$example_name" "$role" "$step_name" "$fixture_name"
done <<EOF
$(example_rows)
EOF
