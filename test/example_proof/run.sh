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

case "$(uname -m)" in
  arm64|aarch64)
    asm_file="$repo_root/src/runtime/aarch64_switch.S"
    ;;
  x86_64|amd64)
    asm_file="$repo_root/src/runtime/x86_64_switch.S"
    ;;
  *)
    echo "unsupported host arch for example proof: $(uname -m)" >&2
    exit 1
    ;;
esac

example_rows() {
  cat <<'EOF'
early_exit.zig|primary|run-early-exit|early_exit.txt
generator.zig|extra|run-generator|generator.txt
nested_workflow.zig|primary|run-nested-workflow|nested_workflow.txt
resume_or_return.zig|primary|run-resume-or-return|resume_or_return.txt
state_basic.zig|primary|run-state-basic|state_basic.txt
EOF
}

check_example_classification() {
  actual_file="$(mktemp)"
  classified_file="$(mktemp)"

  find "$example_dir" -maxdepth 1 -type f -name '*.zig' -exec basename {} \; | sort >"$actual_file"
  example_rows | while IFS='|' read -r example_name _ _ _; do
    [ -n "$example_name" ] || continue
    printf '%s\n' "$example_name"
  done | sort >"$classified_file"

  if ! diff -u "$classified_file" "$actual_file" >/dev/null; then
    echo "example proof registry is out of sync with examples/" >&2
    diff -u "$classified_file" "$actual_file" >&2 || true
    rm -f "$actual_file" "$classified_file"
    exit 1
  fi

  rm -f "$actual_file" "$classified_file"
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

  if ! zig run \
    -ODebug \
    --dep shift \
    -Mroot="$example_path" \
    "$asm_file" \
    -Mshift="$repo_root/src/root.zig" \
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

check_example_classification

while IFS='|' read -r example_name role step_name fixture_name; do
  [ -n "$example_name" ] || continue
  run_example "$example_name" "$role" "$step_name" "$fixture_name"
done <<EOF
$(example_rows)
EOF
