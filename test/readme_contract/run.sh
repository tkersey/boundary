#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
readme="$repo_root/README.md"
build_file="$repo_root/build.zig"

[ -f "$readme" ] || {
  echo "missing README.md" >&2
  exit 1
}

grep -q '^## Proof Surface$' "$readme"
grep -q '^## Executable Contract$' "$readme"
grep -q '^## Benchmark Contract$' "$readme"
grep -q '^## Formal Core$' "$readme"
grep -q 'zig build compile-fail' "$readme"
grep -q 'zig build example-proof' "$readme"
grep -q 'zig build formal-core-write' "$readme"
grep -q 'zig build formal-core' "$readme"
grep -q 'zig build run-optional-basic' "$readme"
grep -q 'zig build bench-state-effect-write' "$readme"
grep -q 'zig build bench-state-effect-check' "$readme"
grep -q 'effect_optional_forged_context_request_fails.zig' "$readme"
grep -q 'effect_reader_forged_context_ask_fails.zig' "$readme"
grep -q 'effect_state_forged_context_get_fails.zig' "$readme"
grep -q 'FORMAL_CORE.md' "$readme"

grep -q 'formal-core-write' "$build_file"
grep -q 'formal-core' "$build_file"
grep -q 'bench-state-effect-write' "$build_file"
grep -q 'bench-state-effect-check' "$build_file"
grep -q 'run-optional-basic' "$build_file"
