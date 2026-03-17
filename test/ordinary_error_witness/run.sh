#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
tool="$repo_root/zig-out/bin/shift-ordinary-lower"

[ -x "$tool" ] || {
  echo "missing shift-ordinary-lower tool" >&2
  exit 1
}

json_out="$(mktemp "${TMPDIR:-/tmp}/shift-ordinary-witness.XXXXXX")"
trap 'rm -f "$json_out"' EXIT INT TERM

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

grep -F -q '"error_witness":{"schema_version":1,"surface":"ordinary","support_status":"supported"' "$json_out"
grep -F -q '"public_runtime_errors":["MissingPrompt","CrossThread","RuntimeBusy","RuntimeDestroyed","NonDiagonalComplete"]' "$json_out"
grep -F -q '"setup_error_names":[]' "$json_out"
grep -F -q '"semantic_error_names":[]' "$json_out"
