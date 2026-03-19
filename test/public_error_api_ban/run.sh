#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

if rg -n 'shift\.Error\b|shift\.WithResult\b|shift\.ControlError\b|shift\.ResetError\(' README.md examples docs src/root.zig src/shift_module.zig src/witness_sources.zig test/size_check.zig src/source_lowering.zig >/dev/null; then
  echo "banned legacy public error API spelling found" >&2
  exit 1
fi

zig run tools/check_public_api_ban.zig >/dev/null
