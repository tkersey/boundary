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

import_matches="$(
  cd "$repo_root"
  rg -n '@import\("raw\.zig"\)' \
    src/frontend.zig \
    src/root.zig \
    || true
)"

if [ -n "$matches" ] || [ -n "$import_matches" ]; then
  echo "canonical modules still call raw.reset/raw.shift:" >&2
  echo "$matches" >&2
  echo "$import_matches" >&2
  exit 1
fi
