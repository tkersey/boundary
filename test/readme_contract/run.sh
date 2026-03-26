#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
readme="$repo_root/README.md"
build_file="$repo_root/build.zig"

[ -f "$readme" ] || {
  echo "missing README.md" >&2
  exit 1
}

grep -q '^## Proof Surface$' "$readme"
grep -q '^## Executable Contract$' "$readme"
grep -q '^## Benchmark Contract$' "$readme"
grep -q '^## Formal Core$' "$readme"

grep -q 'the public front door is rooted in `shift.Program(.{ ... }, Body)` and' "$readme"
grep -q '`shift.run(&runtime, Program, bindings)`' "$readme"
grep -q '`shift.Decl.state`' "$readme"
grep -q '`shift.Decl.family(.{ ... })`' "$readme"
grep -q '`shift.Op.Transform` / `shift.Op.Choice` / `shift.Op.Abort`' "$readme"
grep -q '`shift.Decision(...)`' "$readme"
grep -q 'The legacy compatibility window is now closed.' "$readme"
grep -q 'one root-front-door authoring story' "$readme"

! grep -q '`Program.Manifest`' "$readme"
! grep -q 'shift.with(' "$readme"
! grep -q 'shift.effect.' "$readme"
! grep -q 'shift.algebraic.' "$readme"
! grep -q 'shift.ordinary' "$readme"
! grep -q 'ordinary-Zig experimental track' "$readme"

grep -q 'zig build source-lowering-gauntlet' "$readme"
grep -q 'zig build source-lowering-coverage-check' "$readme"
grep -q 'zig build source-lower' "$readme"
grep -q 'zig build source-lowering-error-witness-check' "$readme"
grep -q 'zig build bench-family-matrix' "$readme"
grep -q 'zig build bench-family-matrix-stability' "$readme"
grep -q 'zig build bench-family-matrix-write' "$readme"
grep -q 'zig build bench-family-matrix-check' "$readme"
grep -q 'zig build shared-declaration-engine-boundary' "$readme"

grep -q 'source-lowering corpus' "$readme"
grep -q 'docs/direct_style_boundary.md' "$readme"
grep -q 'docs/source_lowering_contract.md' "$readme"

grep -q 'source-lowering-gauntlet' "$build_file"
grep -q 'source-lowering-coverage-check' "$build_file"
grep -q 'source-lower' "$build_file"
grep -q 'source-lowering-error-witness-check' "$build_file"
grep -q 'bench-family-matrix' "$build_file"
grep -q 'bench-family-matrix-stability' "$build_file"
grep -q 'bench-family-matrix-write' "$build_file"
grep -q 'bench-family-matrix-check' "$build_file"
grep -q 'bench-family-builder-decompose' "$build_file"
grep -q 'shared-declaration-engine-boundary' "$build_file"

! grep -q 'ordinary-zig-gauntlet' "$build_file"
! grep -q 'ordinary-lower' "$build_file"
! grep -q 'ordinary-error-witness-check' "$build_file"
! grep -q 'bench-effect-matrix' "$build_file"
! grep -q 'bench-algebraic-decompose' "$build_file"
! grep -q 'shared-algebraic-engine-boundary' "$build_file"
