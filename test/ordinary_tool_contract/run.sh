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
external_cwd="$(mktemp -d "${TMPDIR:-/tmp}/shift-ordinary-tool-cwd.XXXXXX")"
trap 'rm -f "$rejected_out" "$accepted_out" "$json_out" "$quoted_alias"; rm -rf "$external_cwd"' EXIT INT TERM

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
grep -F -q '"case_id":"ordinary.branch_resume"' "$json_out"
grep -F -q '"surface_kind":"ordinary_case"' "$json_out"
grep -F -q '"status":"rejected"' "$json_out"
grep -F -q '"diagnostics":[{"code":"non_canonical_source_path"' "$json_out"
grep -F -q '"path":"' "$json_out"

(
  cd "$external_cwd"
  "$tool" \
    --id example.algebraic_abortive_validation \
    --source "$repo_root/examples/algebraic_abortive_validation.zig" \
    --entry run \
    --surface example \
    --emit zig \
    --out "$accepted_out"
)

grep -F -q 'expected_transcript = "validate=name\nabort=missing-name\nfinal=error=missing-name\n"' "$accepted_out"

(
  cd "$repo_root/examples"
  "$tool" \
    --id example.define_basic \
    --source define_basic.zig \
    --entry run \
    --surface example \
    --emit json \
    --out "$json_out"
)

grep -F -q '"case_id":"example.define_basic"' "$json_out"
grep -F -q '"status":"canonical"' "$json_out"

zig fmt "$accepted_out" >/dev/null
grep -F -q 'const shift = @import("shift");' "$accepted_out"
if rg -q 'ordinary_zig_lowering|lowered_machine' "$accepted_out"; then
  echo "expected emitted Zig to depend only on the public shift module" >&2
  exit 1
fi
grep -F -q 'pub fn initGeneratedProgram(allocator: std.mem.Allocator) !shift.ordinary.GeneratedProgram {' "$accepted_out"
grep -F -q 'var generated_program = try initGeneratedProgram(allocator);' "$accepted_out"
grep -F -q '.steps = try allocator.dupe(shift.ordinary.Step, &generated_program_steps),' "$accepted_out"
grep -F -q '.diagnostics = try allocator.dupe(shift.ordinary.Diagnostic, &generated_program_diagnostics),' "$accepted_out"

zig run tools/check_public_api_ban.zig >/dev/null
