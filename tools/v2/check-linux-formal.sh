#!/bin/sh
# Reproduce the implemented formal/compiler gates on Linux, without Docker.
# The complete profile and World execution certifiers remain separate work.
set -eu
if [ "$#" -ne 0 ]; then
    echo 'usage: sh tools/v2/check-linux-formal.sh' >&2
    exit 64
fi
if [ "$(uname -s)/$(uname -m)" != Linux/x86_64 ]; then
    echo 'Linux x86-64 is required' >&2
    exit 2
fi
proof_root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$proof_root"
proof_jobs="${BOUNDARY_PROOF_JOBS:-2}"
case "$proof_jobs" in ''|*[!0-9]*|0) echo 'invalid BOUNDARY_PROOF_JOBS' >&2; exit 64;; esac
proof_lean="$(lean --version)"
case "$proof_lean" in *'version 4.33.1,'*'commit 819816b2e0a3bf405af45ae5c7af2491d8f5bee6,'*) ;;
    *) echo 'Lean toolchain identity mismatch' >&2; exit 2;; esac
[ "$(zig version)" = 0.16.0 ] || { echo 'Zig version mismatch' >&2; exit 2; }
[ "$(node --version)" = v26.8.1 ] || { echo 'Node version mismatch' >&2; exit 2; }
printf 'platform=%s\nscope=implemented-formal-and-compiler-gates\n%s\n' "$(uname -sm)" "$proof_lean"
zig version
node --version
if git rev-parse --verify HEAD 2>/dev/null; then git status --short; fi
sha256sum "$(command -v leanchecker)"
printf 'command=zig build check-v2 -j%s --summary all\n' "$proof_jobs"
zig build check-v2 "-j$proof_jobs" --summary all
