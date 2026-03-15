#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

matches="$(
  cd "$repo_root"
  rg -n 'raw\.(reset|shift)' \
    src/frontend.zig \
    src/root.zig \
    src/effect/algebraic.zig \
    src/algebraic.zig \
    || true
)"

if [ -n "$matches" ]; then
  echo "canonical modules still call raw.reset/raw.shift:" >&2
  echo "$matches" >&2
  exit 1
fi
