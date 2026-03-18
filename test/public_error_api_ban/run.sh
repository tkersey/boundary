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

ban_regex='shift\.algebraic\.Program\([^,]+,\s*(NoError|error\{[^}]*\}|[A-Za-z_][A-Za-z0-9_.]*)\s*,\s*\.\{'
if rg -nP "$ban_regex" README.md examples test/size_check.zig src/ordinary_zig_lowering.zig >/dev/null; then
  echo "banned explicit algebraic Program ErrorSet spelling found" >&2
  exit 1
fi

probe="$(mktemp "${TMPDIR:-/tmp}/shift-public-error-api-ban.XXXXXX")"
trap 'rm -f "$probe"' EXIT INT TERM
cat >"$probe" <<'EOF'
const shift = @import("shift");
const ping = shift.algebraic.TransformOp("ping", void, i32);
const bad = shift.algebraic.Program(i32, error{Oops}, .{ping});
EOF

if ! rg -nP "$ban_regex" "$probe" >/dev/null; then
  echo "expected explicit algebraic Program ErrorSet probe to be rejected" >&2
  exit 1
fi

cat >"$probe" <<'EOF'
const shift = @import("shift");
const ping = shift.algebraic.TransformOp("ping", void, i32);
const Errs = error{Oops};
const bad = shift.algebraic.Program(i32, Errs, .{ping});
EOF

if ! rg -nP "$ban_regex" "$probe" >/dev/null; then
  echo "expected explicit algebraic Program ErrorSet alias probe to be rejected" >&2
  exit 1
fi
