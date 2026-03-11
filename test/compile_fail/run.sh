#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

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

run_fixture "$repo_root/test/compile_fail/pending_deinit_forbidden.zig" "deinit"
run_fixture "$repo_root/test/compile_fail/pending_discontinue_empty_error_set.zig" "discontinue"
run_fixture "$repo_root/test/compile_fail/pending_resume_with_void_forbidden.zig" "resumeWith"
run_fixture "$repo_root/test/compile_fail/escaped_discontinue_empty_error_set.zig" "discontinue"
run_fixture "$repo_root/test/compile_fail/escaped_resume_with_void_forbidden.zig" "resumeWith"
run_fixture "$repo_root/test/compile_fail/escaped_token_removed.zig" "EscapedToken"
run_fixture "$repo_root/test/compile_fail/reset_removed.zig" "reset"
run_fixture "$repo_root/test/compile_fail/shift_removed.zig" "shift"
run_fixture "$repo_root/test/compile_fail/token_aliased_removed.zig" "TokenAliased"
