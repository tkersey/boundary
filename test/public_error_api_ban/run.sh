#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

if rg -n 'shift\.Error\b|shift\.WithResult\b|shift\.ControlError\b|shift\.ResetError\(' README.md examples docs src/root.zig src/shift_module.zig test/lexical_with_test.zig test/lexical_witness_support.zig src/witness_sources.zig >/dev/null; then
  echo "banned legacy public error API spelling found" >&2
  exit 1
fi

if rg -n 'shift\.effect\.(state|reader|writer|optional|exception|resource)\.use\([^)]*NoError' README.md examples test/lexical_with_test.zig test/lexical_witness_support.zig src/witness_sources.zig src/internal/compat_witness_runners.zig >/dev/null; then
  echo "banned explicit NoError lexical use(...) spelling found" >&2
  exit 1
fi

if rg -n 'shift\.algebraic\.Program\([^,]+,\s*NoError,' README.md examples test/size_check.zig src/ordinary_zig_lowering.zig >/dev/null; then
  echo "banned explicit algebraic Program ErrorSet spelling found" >&2
  exit 1
fi
