#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

case "$(uname -m)" in
  arm64|aarch64)
    asm_file="$repo_root/src/runtime/aarch64_switch.S"
    ;;
  x86_64|amd64)
    asm_file="$repo_root/src/runtime/x86_64_switch.S"
    ;;
  *)
    echo "unsupported host arch for compile-fail harness: $(uname -m)" >&2
    exit 1
    ;;
esac

run_fixture() {
  fixture="$1"
  expected="$2"
  stderr_file="$(mktemp)"
  trap 'rm -f "$stderr_file"' EXIT INT TERM

  if zig build-obj \
    -ODebug \
    -fno-emit-bin \
    --dep shift \
    -Mroot="$fixture" \
    "$asm_file" \
    -Mshift="$repo_root/src/root.zig" \
    --cache-dir "$repo_root/.zig-cache" \
    --global-cache-dir "${HOME}/.cache/zig" \
    --name compile-fail-fixture \
    > /dev/null 2>"$stderr_file"
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

run_fixture "$repo_root/test/compile_fail/continuation_discontinue_removed.zig" "discontinue"
run_fixture "$repo_root/test/compile_fail/no_shift_guard_removed.zig" "NoShiftGuard"
run_fixture "$repo_root/test/compile_fail/resume_value_mismatch.zig" "expected type"
