#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

scan_paths='README.md examples src/root.zig src/shift_module.zig src/witness_sources.zig test/size_check.zig src/source_lowering.zig'
pattern='shift\.Error\b|shift\.WithResult\b|shift\.ControlError\b|shift\.ResetError\('

set +e
rg -n "$pattern" $scan_paths >/dev/null
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "banned legacy public error API spelling found" >&2
  exit 1
fi

if [ "$status" -ne 1 ]; then
  echo "public error API ban scan failed to run" >&2
  exit "$status"
fi

zig run tools/check_public_api_ban.zig >/dev/null
