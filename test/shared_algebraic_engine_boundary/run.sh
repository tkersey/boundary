#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

rg -q '@import\("internal/algebraic_engine\.zig"\)' "$repo_root/src/algebraic.zig"
rg -q '@import\("\.\./internal/algebraic_engine\.zig"\)' "$repo_root/src/effect/algebraic.zig"
rg -q '@import\("\.\./internal/algebraic_engine\.zig"\)' "$repo_root/src/effect/generated_family.zig"
rg -q '@import\("generated_family\.zig"\)' "$repo_root/src/effect/define.zig"

if rg -n '@import\("kernel\.zig"\)|kernel\.' "$repo_root/src/effect" >/dev/null; then
  echo "shared algebraic engine boundary violated by lingering kernel usage" >&2
  exit 1
fi

if ! rg -n 'internal\.Program\(' "$repo_root/src/effect/algebraic.zig" >/dev/null; then
  echo "shared algebraic engine boundary missing hidden effect programs" >&2
  exit 1
fi

if ! rg -n 'internal\.Program\(' "$repo_root/src/effect/generated_family.zig" >/dev/null; then
  echo "shared algebraic engine boundary missing generated-family hidden programs" >&2
  exit 1
fi

for file in \
  "$repo_root/src/effect/state.zig" \
  "$repo_root/src/effect/reader.zig" \
  "$repo_root/src/effect/optional.zig" \
  "$repo_root/src/effect/exception.zig" \
  "$repo_root/src/effect/resource.zig" \
  "$repo_root/src/effect/writer.zig"
do
  if rg -n '@import\("\.\./internal/algebraic_engine\.zig"\)|@import\("kernel\.zig"\)|@import\("cleanup\.zig"\)|@import\("\.\./frontend\.zig"\)' "$file" >/dev/null; then
    echo "effect leaf bypasses the shared engine/sealing boundary in $file" >&2
    exit 1
  fi
done

if rg -n '@import\("\.\./internal/algebraic_engine\.zig"\)|@import\("cleanup\.zig"\)|@import\("\.\./frontend\.zig"\)' "$repo_root/src/effect/define.zig" >/dev/null; then
  echo "public define surface bypasses the shared engine/sealing boundary" >&2
  exit 1
fi
