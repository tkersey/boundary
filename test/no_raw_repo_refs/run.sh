#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

matches="$(
  cd "$repo_root"
  rg -n 'src/raw\.zig|src/compat/raw\.zig|raw_core_module\.zig|shift_swap_context|@import\("raw\.zig"\)|raw\.(Prompt|PromptMode|ResumeOrReturn|Error|ControlError|ResetError|Runtime|reset|shift|shiftLocalIdentity|SetupError)\b|compat_raw_only|compat_raw\b' \
    src \
    test \
    README.md \
    FORMAL_CORE.md \
    docs \
    build.zig \
    examples \
    bench \
    --glob '!test/no_raw_repo_refs/run.sh' \
    || true
)"

if [ -n "$matches" ]; then
  echo "repo still contains deleted raw runtime references:" >&2
  echo "$matches" >&2
  exit 1
fi
