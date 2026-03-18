#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
tool="$repo_root/zig-out/bin/shift-ordinary-lower"

[ -x "$tool" ] || {
  echo "missing shift-ordinary-lower tool" >&2
  exit 1
}

typed_out="$(mktemp "${TMPDIR:-/tmp}/shift-ordinary-typed.XXXXXX")"
errdefer_out="$(mktemp "${TMPDIR:-/tmp}/shift-ordinary-errdefer.XXXXXX")"
with_out="$(mktemp "${TMPDIR:-/tmp}/shift-ordinary-with.XXXXXX")"
program_out="$(mktemp "${TMPDIR:-/tmp}/shift-ordinary-program.XXXXXX")"
trap 'rm -f "$typed_out" "$errdefer_out" "$with_out" "$program_out"' EXIT INT TERM

(
  cd "$repo_root"
  "$tool" \
    --id ordinary.typed_error_try \
    --source test/ordinary_zig_corpus/fixtures/typed_error_try.zig \
    --entry run \
    --surface ordinary_case \
    --emit json \
    --out "$typed_out"
)

(
  cd "$repo_root"
  "$tool" \
    --id ordinary.errdefer_error \
    --source test/ordinary_zig_corpus/fixtures/errdefer_error.zig \
    --entry run \
    --surface ordinary_case \
    --emit json \
    --out "$errdefer_out"
)

(
  cd "$repo_root/examples"
  "$tool" \
    --id example.define_basic \
    --source define_basic.zig \
    --entry run \
    --surface example \
    --emit json \
    --out "$with_out"
  "$tool" \
    --id example.algebraic_artifact_search \
    --source algebraic_artifact_search.zig \
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
