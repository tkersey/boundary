#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

run_fixture() {
  fixture="$1"
  expected="$2"
  stderr_file="$(mktemp)"
  trap 'rm -f "$stderr_file"' EXIT INT TERM

  if zig run \
    --dep compiler \
    -Mroot="$repo_root/tool/shiftc.zig" \
    -Mcompiler="$repo_root/src/compiler.zig" \
    -- \
    --input "$fixture" \
    --zig "$repo_root/.zig-cache/compile-fail.zig" \
    --map "$repo_root/.zig-cache/compile-fail.map.json" \
    --cert "$repo_root/.zig-cache/compile-fail.linear.json" \
    >"$stderr_file" 2>&1
  then
    echo "expected compile failure: $fixture" >&2
    cat "$stderr_file" >&2
    exit 1
  fi

  if ! grep -q "$expected" "$stderr_file"; then
    echo "missing expected error marker '$expected' for $fixture" >&2
    cat "$stderr_file" >&2
    exit 1
  fi

  rm -f "$stderr_file"
  trap - EXIT INT TERM
}

run_fixture "$repo_root/test/compile_fail/double_resume.shift" "linear use of resume"
run_fixture "$repo_root/test/compile_fail/unhandled_effect.shift" "unhandled effect"
