#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
tool="$repo_root/zig-out/bin/shift-source-lower"

[ -x "$tool" ] || {
  echo "missing shift-source-lower tool" >&2
  exit 1
}

one="$(mktemp "${TMPDIR:-/tmp}/shift-error-witness-one.XXXXXX")"
two="$(mktemp "${TMPDIR:-/tmp}/shift-error-witness-two.XXXXXX")"
trap 'rm -f "$one" "$two"' EXIT INT TERM

(
  cd "$repo_root/examples"
  "$tool" \
    --id example.define_basic \
    --source define_basic.zig \
    --entry run \
    --surface example \
    --emit json \
    --out "$one"
  "$tool" \
    --id example.algebraic_abortive_validation \
    --source algebraic_abortive_validation.zig \
    --entry run \
    --surface example \
    --emit json \
    --out "$two"
)

uv run python - <<'PY' "$one" "$two"
import json, sys
one = json.load(open(sys.argv[1]))
two = json.load(open(sys.argv[2]))
for doc in (one, two):
    ew = doc["error_witness"]
    assert ew["schema_version"] == 1
    assert ew["surface"] == "ordinary"
    assert ew["support_status"] == "supported"
assert one["error_witness"]["public_runtime_errors"] == two["error_witness"]["public_runtime_errors"]
assert one["error_witness"]["public_runtime_errors"] == []
assert one["error_witness"]["setup_error_names"] == two["error_witness"]["setup_error_names"]
assert one["error_witness"]["setup_error_names"] == ["OutOfMemory"]
assert one["error_witness"]["semantic_error_names"] == []
assert two["error_witness"]["semantic_error_names"] == []
PY
