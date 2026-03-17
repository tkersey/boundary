#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
tool="$repo_root/zig-out/bin/shift-ordinary-lower"

[ -x "$tool" ] || {
  echo "missing shift-ordinary-lower tool" >&2
  exit 1
}

rejected_out="$(mktemp "${TMPDIR:-/tmp}/shift-ordinary-tool-rejected.XXXXXX")"
accepted_out="$(mktemp "${TMPDIR:-/tmp}/shift-ordinary-tool-accepted.XXXXXX")"
json_out="$(mktemp "${TMPDIR:-/tmp}/shift-ordinary-tool-json.XXXXXX")"
quoted_alias="$(mktemp "${TMPDIR:-/tmp}/tmp-bad-quoted.XXXXXX")\"bad\""
portable_root="$(mktemp -d "${TMPDIR:-/tmp}/shift-ordinary-tool-portable.XXXXXX")"
trap 'rm -f "$rejected_out" "$accepted_out" "$json_out" "$quoted_alias"; rm -rf "$portable_root"' EXIT INT TERM

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

rm -f "$quoted_alias"
cp "$repo_root/test/ordinary_zig_corpus/fixtures/branch_resume.zig" "$quoted_alias"

if "$tool" \
  --id ordinary.branch_resume \
  --source "$quoted_alias" \
  --entry run \
  --surface ordinary_case \
  --emit json \
  --out "$json_out" \
  2>/dev/null
then
  echo "expected rejected ordinary tool json run to fail" >&2
  exit 1
fi

grep -q '\\\"bad\\\"' "$json_out"
jq -e . "$json_out" >/dev/null

(
  mkdir -p "$portable_root/examples"
  cp "$repo_root/examples/algebraic_abortive_validation.zig" "$portable_root/examples/algebraic_abortive_validation.zig"
  cd "$portable_root"
  "$tool" \
    --id example.algebraic_abortive_validation \
    --source examples/algebraic_abortive_validation.zig \
    --entry run \
    --surface example \
    --emit zig \
    --out "$accepted_out"
)

grep -F -q 'expected_transcript = "validate=name\nabort=missing-name\nfinal=error=missing-name\n"' "$accepted_out"
grep -F -q 'pub fn initGeneratedProgram(allocator: std.mem.Allocator) !ordinary.GeneratedProgram {' "$accepted_out"
grep -F -q 'var generated_program = try initGeneratedProgram(allocator);' "$accepted_out"
grep -F -q '.steps = try allocator.dupe(lowered_machine.Step, &generated_program_steps),' "$accepted_out"
grep -F -q '.diagnostics = try allocator.dupe(ordinary.Diagnostic, &generated_program_diagnostics),' "$accepted_out"
