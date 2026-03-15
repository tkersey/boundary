#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
readme="$repo_root/README.md"
build_file="$repo_root/build.zig"
obligation_matrix="$repo_root/docs/runtime_obligation_matrix.json"
survey_harness="$repo_root/test/one_shot_survey/run.sh"
compile_fail_harness="$repo_root/test/compile_fail/run.sh"

[ -f "$readme" ] || { echo "missing README.md" >&2; exit 1; }
[ -f "$build_file" ] || { echo "missing build.zig" >&2; exit 1; }
[ -f "$obligation_matrix" ] || { echo "missing docs/runtime_obligation_matrix.json" >&2; exit 1; }

if grep -q '"status":"stack_backend_required"' "$obligation_matrix"; then
  echo "shipped backend still blocked by runtime_obligation_matrix" >&2
  exit 1
fi

if grep -q 'The current runtime backend is stackful' "$readme"; then
  echo "README still says the current runtime backend is stackful" >&2
  exit 1
fi

if grep -q 'addRuntimeAssembly' "$build_file"; then
  echo "build.zig still wires stack-switch assembly into the shipped path" >&2
  exit 1
fi

if grep -q 'asm_file=' "$survey_harness"; then
  echo "one_shot_survey harness still injects stack runtime assembly" >&2
  exit 1
fi

if grep -q 'asm_file=' "$compile_fail_harness"; then
  echo "compile_fail harness still injects stack runtime assembly" >&2
  exit 1
fi
