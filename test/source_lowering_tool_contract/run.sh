#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
tool="$repo_root/zig-out/bin/shift-source-lower"

[ -x "$tool" ] || {
  echo "missing shift-source-lower tool" >&2
  exit 1
}

rejected_dir="$(mktemp -d "${TMPDIR:-/tmp}/shift-source-lowering-tool-rejected.XXXXXX")"
rejected_out="$rejected_dir/rejected_out.zig"
accepted_out="$(mktemp "${TMPDIR:-/tmp}/shift-source-lowering-tool-accepted.XXXXXX")"
json_out="$(mktemp "${TMPDIR:-/tmp}/shift-source-lowering-tool-json.XXXXXX")"
quoted_alias="$(mktemp "${TMPDIR:-/tmp}/tmp-bad-quoted.XXXXXX")\"bad\""
external_cwd="$(mktemp -d "${TMPDIR:-/tmp}/shift-source-lowering-tool-cwd.XXXXXX")"
trap 'rm -f "$accepted_out" "$json_out" "$quoted_alias"; rm -rf "$rejected_dir" "$external_cwd"' EXIT INT TERM

if "$tool" \
  --id source.branch_resume \
  --source test/source_lowering_corpus/fixtures/helper_call_resume.zig \
  --entry run \
  --surface source_case \
  --emit zig \
  --out "$rejected_out" \
  2>/dev/null
then
  echo "expected rejected source-lowering tool run to fail" >&2
  exit 1
fi

grep -q 'non_canonical_source_path' "$rejected_out"
grep -q 'source path does not match the canonical repo-owned path for this case' "$rejected_out"

rm -f "$quoted_alias"
cp "$repo_root/test/source_lowering_corpus/fixtures/branch_resume.zig" "$quoted_alias"

if "$tool" \
  --id source.branch_resume \
  --source "$quoted_alias" \
  --entry run \
  --surface source_case \
  --emit json \
  --out "$json_out" \
  2>/dev/null
then
  echo "expected rejected source-lowering tool json run to fail" >&2
  exit 1
fi

uv run python - <<'PY' "$json_out"
import json, sys

doc = json.load(open(sys.argv[1]))
assert doc["case_id"] == "source.branch_resume"
assert doc["surface_kind"] == "source_case"
assert doc["status"] == "rejected"
assert len(doc["diagnostics"]) == 1
assert doc["diagnostics"][0]["code"] == "non_canonical_source_path"
assert '"bad"' in doc["diagnostics"][0]["path"]
ew = doc["error_witness"]
assert ew["support_status"] == "unsupported"
assert ew["public_runtime_errors"] == []
assert ew["setup_error_names"] == []
assert ew["semantic_error_names"] == []
assert ew["contributors"] == []
assert len(ew["diagnostics"]) == 1
assert ew["diagnostics"][0]["code"] == "non_canonical_source_path"
assert ew["diagnostics"][0]["path"] == doc["diagnostics"][0]["path"]
PY

grep -F -q 'const generated_program_witness_diagnostics = [_]WitnessDiagnostic{' "$rejected_out"
grep -F -q '.diagnostics = try allocator.dupe(WitnessDiagnostic, &generated_program_witness_diagnostics)' "$rejected_out"

(
  cd "$external_cwd"
  "$tool" \
    --id example.resource_basic \
    --source "$repo_root/examples/resource_basic.zig" \
    --entry run \
    --surface example \
    --emit zig \
    --out "$accepted_out"
)

grep -F -q 'expected_transcript = "acquire=a\nuse=a\nacquire=b\nuse=b\nrelease=b\nrelease=a\nfinal=done\n"' "$accepted_out"

(
  cd "$repo_root/examples"
  "$tool" \
    --id example.state_basic \
    --source state_basic.zig \
    --entry run \
    --surface example \
    --emit json \
    --out "$json_out"
)

uv run python - <<'PY' "$json_out"
import json, sys

doc = json.load(open(sys.argv[1]))
assert doc["case_id"] == "example.state_basic"
assert doc["status"] == "canonical"
ew = doc["error_witness"]
assert ew["public_runtime_errors"] == []
assert ew["setup_error_names"] == ["OutOfMemory"]
assert ew["semantic_error_names"] == []
assert ew["contributors"] == []
assert ew["diagnostics"] == []
PY

zig fmt "$accepted_out" >/dev/null
grep -F -q 'const source_lowering = @import("source_lowering");' "$accepted_out"
if rg -q 'lowered_machine' "$accepted_out"; then
  echo "expected emitted Zig to depend only on the internal source_lowering module and std" >&2
  exit 1
fi
grep -F -q 'pub fn initGeneratedProgram(allocator: std.mem.Allocator) !source_lowering.GeneratedProgram {' "$accepted_out"
grep -F -q 'var generated_program = try initGeneratedProgram(allocator);' "$accepted_out"
grep -F -q '.steps = try allocator.dupe(source_lowering.Step, &generated_program_steps),' "$accepted_out"
grep -F -q '.diagnostics = try allocator.dupe(source_lowering.Diagnostic, &generated_program_diagnostics),' "$accepted_out"
grep -F -q '.setup_error_names = &.{"OutOfMemory"}' "$accepted_out"
grep -F -q '.semantic_error_names = &.{}, .contributors = &.{}, .diagnostics = &.{} },' "$accepted_out"

zig run tools/check_public_api_ban.zig >/dev/null
