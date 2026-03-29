#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
tool="$repo_root/zig-out/bin/shift-source-lower"

[ -x "$tool" ] || {
  echo "missing shift-source-lower tool" >&2
  exit 1
}

typed_out="$(mktemp "${TMPDIR:-/tmp}/shift-source-lowering-typed.XXXXXX")"
errdefer_out="$(mktemp "${TMPDIR:-/tmp}/shift-source-lowering-errdefer.XXXXXX")"
with_out="$(mktemp "${TMPDIR:-/tmp}/shift-source-lowering-with.XXXXXX")"
program_out="$(mktemp "${TMPDIR:-/tmp}/shift-source-lowering-program.XXXXXX")"
trap 'rm -f "$typed_out" "$errdefer_out" "$with_out" "$program_out"' EXIT INT TERM

(
  cd "$repo_root"
  "$tool" \
    --id source.typed_error_try \
    --source test/source_lowering_corpus/fixtures/typed_error_try.zig \
    --entry run \
    --surface source_case \
    --emit json \
    --out "$typed_out"
)

(
  cd "$repo_root"
  "$tool" \
    --id source.errdefer_error \
    --source test/source_lowering_corpus/fixtures/errdefer_error.zig \
    --entry run \
    --surface source_case \
    --emit json \
    --out "$errdefer_out"
)

(
  cd "$repo_root/examples"
  "$tool" \
    --id example.open_row_transform_basic \
    --source open_row_transform_basic.zig \
    --entry run \
    --surface example \
    --emit json \
    --out "$with_out"
  "$tool" \
    --id example.open_row_artifact_search \
    --source open_row_artifact_search.zig \
    --entry run \
    --surface example \
    --emit json \
    --out "$program_out"
)

uv run python - <<'PY' "$typed_out" "$errdefer_out" "$with_out" "$program_out"
import json, sys

typed = json.load(open(sys.argv[1]))
errdefer = json.load(open(sys.argv[2]))
with_doc = json.load(open(sys.argv[3]))
program_doc = json.load(open(sys.argv[4]))

typed_ew = typed["error_witness"]
assert typed_ew["surface"] == "ordinary"
assert typed_ew["support_status"] == "supported"
assert typed_ew["public_runtime_errors"] == []
assert typed_ew["setup_error_names"] == []
assert typed_ew["semantic_error_names"] == ["Boom"]
assert typed_ew["contributors"] == [
    {
        "kind": "body",
        "surface": "ordinary",
        "symbol": "fail",
        "error_names": ["Boom"],
    }
]

errdefer_ew = errdefer["error_witness"]
assert errdefer_ew["setup_error_names"] == []
assert errdefer_ew["semantic_error_names"] == ["Boom"]
assert errdefer_ew["contributors"] == [
    {
        "kind": "body",
        "surface": "ordinary",
        "symbol": "body",
        "error_names": ["Boom"],
    }
]

with_ew = with_doc["error_witness"]
assert with_ew["public_runtime_errors"] == []
assert with_ew["setup_error_names"] == ["OutOfMemory"]
assert with_ew["semantic_error_names"] == []

program_ew = program_doc["error_witness"]
assert program_ew["public_runtime_errors"] == []
assert program_ew["setup_error_names"] == ["OutOfMemory"]
assert program_ew["semantic_error_names"] == []
PY
