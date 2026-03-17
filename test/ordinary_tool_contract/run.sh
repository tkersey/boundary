#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
tool="$repo_root/zig-out/bin/shift-ordinary-lower"

[ -x "$tool" ] || {
  echo "missing shift-ordinary-lower tool" >&2
  exit 1
}

rejected_out="$(mktemp "${TMPDIR:-/tmp}/shift-ordinary-tool-rejected.XXXXXX.zig")"
accepted_out="$(mktemp "${TMPDIR:-/tmp}/shift-ordinary-tool-accepted.XXXXXX.zig")"
trap 'rm -f "$rejected_out" "$accepted_out"' EXIT INT TERM

if "$tool" \
  --id ordinary.branch_resume \
  --source test/ordinary_zig_corpus/fixtures/helper_call_resume.zig \
  --entry run \
  --surface ordinary_case \
  --emit zig \
  --out "$rejected_out" \
  2>/dev/null
then
  echo "expected rejected ordinary tool run to fail" >&2
  exit 1
fi

grep -q 'non_canonical_source_path' "$rejected_out"
grep -q 'source path does not match the canonical repo-owned path for this case' "$rejected_out"

"$tool" \
  --id example.algebraic_abortive_validation \
  --source examples/algebraic_abortive_validation.zig \
  --entry run \
  --surface example \
  --emit zig \
  --out "$accepted_out"

grep -F -q 'expected_transcript = "validate=name\nabort=missing-name\nfinal=error=missing-name\n"' "$accepted_out"
