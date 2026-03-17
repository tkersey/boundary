#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
contract="$repo_root/docs/ordinary_zig_contract.md"

[ -f "$contract" ] || {
  echo "missing ordinary Zig contract" >&2
  exit 1
}

grep -q '^# Ordinary Zig Contract$' "$contract"
grep -q '^## Status$' "$contract"
grep -q '^## Long-Term Canonical Target$' "$contract"
grep -q '^## Preserved Semantic Invariants$' "$contract"
grep -q '^## Wave-One Supported Subset$' "$contract"
grep -q '^## Wave-One Exclusions$' "$contract"
grep -q '^## Surface Replacement Matrix$' "$contract"
grep -q '^## Proof Surface$' "$contract"
grep -q 'public experimental' "$contract"
grep -q 'internal-only restricted lowering path' "$contract"
grep -q 'zig build ordinary-zig-gauntlet' "$contract"
grep -q 'zig build surface-replacement-check' "$contract"
grep -q 'zig build test' "$contract"
grep -q 'ordinary-body generalized algebraic' "$contract"
grep -q 'current lowered machine' "$contract"
grep -q 'static delimitation' "$contract"
grep -q 'one-shot linearity' "$contract"
grep -q 'ordinary.local_mutation_resume' "$contract"
grep -q 'ordinary.branch_resume' "$contract"
grep -q 'ordinary.loop_resume' "$contract"
grep -q 'ordinary.helper_call_resume' "$contract"
grep -q 'ordinary.cross_module_helper_resume' "$contract"
grep -q 'ordinary.cross_module_helper_chain_resume' "$contract"
grep -q 'ordinary.nested_prompt_static_redelim' "$contract"
grep -q 'ordinary.typed_error_try' "$contract"
grep -q 'ordinary.cross_module_typed_error_try' "$contract"
grep -q 'ordinary.defer_resume' "$contract"
grep -q 'ordinary.errdefer_error' "$contract"
grep -q 'static imported helper calls and helper chains' "$contract"
grep -q 'typed error propagation through imported helpers' "$contract"
grep -q 'No public continuation handle' "$contract"
grep -q 'No runtime2' "$contract"
grep -q 'No recursion' "$contract"
grep -q 'No dynamic callee lowering' "$contract"
grep -q 'No arbitrary cross-module lowering' "$contract"
grep -q 'No user-invocable lowering entrypoint' "$contract"
grep -q 'No performance contract' "$contract"
grep -q 'docs/surface_replacement_matrix.json' "$contract"
