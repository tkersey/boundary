#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

check_file() {
  file="$1"

  if rg -n '@import\("kernel\.zig"\)|@import\("cleanup\.zig"\)|@import\("\.\./raw\.zig"\)' "$file" >/dev/null; then
    echo "effect construction boundary violated by import in $file" >&2
    exit 1
  fi

  if rg -n '\braw\.|\bkernel\.|\bcleanup\.' "$file" >/dev/null; then
    echo "effect construction boundary violated by direct primitive use in $file" >&2
    exit 1
  fi
}

check_file "$repo_root/src/effect/state.zig"
check_file "$repo_root/src/effect/reader.zig"
check_file "$repo_root/src/effect/optional.zig"
check_file "$repo_root/src/effect/exception.zig"
check_file "$repo_root/src/effect/resource.zig"
check_file "$repo_root/src/effect/writer.zig"
