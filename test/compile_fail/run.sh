#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cache_root="$(mktemp -d "${TMPDIR:-/tmp}/shift-compile-fail-cache.XXXXXX")"
local_cache_dir="$cache_root/local"
global_cache_dir="$cache_root/global"

mkdir -p "$local_cache_dir" "$global_cache_dir"
trap 'rm -rf "$cache_root"' EXIT INT TERM

run_fixture() {
  fixture="$1"
  expected="$2"
  stderr_file="$(mktemp)"

  if zig build-obj \
    -ODebug \
    -fno-emit-bin \
    --dep shift \
    -Mroot="$fixture" \
    --dep parity_scenarios \
    -Mlowered_machine="$repo_root/src/lowered_machine.zig" \
    -Mparity_scenarios="$repo_root/src/parity_scenarios.zig" \
    --dep lowered_machine \
    -Mshift="$repo_root/src/shift_module.zig" \
    --cache-dir "$local_cache_dir" \
    --global-cache-dir "$global_cache_dir" \
    --name compile-fail-fixture \
    > /dev/null 2>"$stderr_file"
  then
    echo "expected compile failure: $fixture" >&2
    cat "$stderr_file" >&2
    rm -f "$stderr_file"
    exit 1
  fi

  if ! grep -q "$expected" "$stderr_file"; then
    echo "missing expected error marker '$expected' for $fixture" >&2
    cat "$stderr_file" >&2
    rm -f "$stderr_file"
    exit 1
  fi

  rm -f "$stderr_file"
}

run_fixture "$repo_root/test/compile_fail/continuation_discontinue_removed.zig" "Continuation"
run_fixture "$repo_root/test/compile_fail/effect_state_continuation_removed.zig" "Continuation"
run_fixture "$repo_root/test/compile_fail/effect_state_context_removed.zig" "Context"
run_fixture "$repo_root/test/compile_fail/effect_state_cross_instance_context_fails.zig" "context capability does not match supplied capability"
run_fixture "$repo_root/test/compile_fail/effect_state_forged_context_get_fails.zig" "expected exact shift.effect context type"
run_fixture "$repo_root/test/compile_fail/effect_state_get_without_context.zig" "expected a pointer to a shift.effect context"
run_fixture "$repo_root/test/compile_fail/effect_state_set_without_context.zig" "expected a pointer to a shift.effect context"
run_fixture "$repo_root/test/compile_fail/effect_reader_context_removed.zig" "Context"
run_fixture "$repo_root/test/compile_fail/effect_reader_cross_instance_context_fails.zig" "context capability does not match supplied capability"
run_fixture "$repo_root/test/compile_fail/effect_reader_forged_context_ask_fails.zig" "expected exact shift.effect context type"
run_fixture "$repo_root/test/compile_fail/effect_reader_ask_without_context.zig" "expected a pointer to a shift.effect context"
run_fixture "$repo_root/test/compile_fail/effect_exception_context_removed.zig" "Context"
run_fixture "$repo_root/test/compile_fail/effect_exception_cross_instance_context_fails.zig" "context capability does not match supplied capability"
run_fixture "$repo_root/test/compile_fail/effect_exception_forged_context_throw_fails.zig" "expected exact shift.effect context type"
run_fixture "$repo_root/test/compile_fail/effect_exception_throw_without_context.zig" "expected a pointer to a shift.effect context"
run_fixture "$repo_root/test/compile_fail/effect_exception_catch_missing_direct_return.zig" "exception catch policy must declare directReturn"
run_fixture "$repo_root/test/compile_fail/effect_exception_catch_wrong_direct_return_type.zig" "exception catch policy directReturn must have type"
run_fixture "$repo_root/test/compile_fail/effect_optional_context_removed.zig" "Context"
run_fixture "$repo_root/test/compile_fail/effect_optional_cross_instance_context_fails.zig" "context capability does not match supplied capability"
run_fixture "$repo_root/test/compile_fail/effect_optional_forged_context_request_fails.zig" "expected exact shift.effect context type"
run_fixture "$repo_root/test/compile_fail/effect_optional_request_without_context.zig" "expected a pointer to a shift.effect context"
run_fixture "$repo_root/test/compile_fail/effect_optional_lexical_missing_apply_fails.zig" "lexical choice continuation must declare apply"
run_fixture "$repo_root/test/compile_fail/effect_optional_lexical_wrong_apply_arity_fails.zig" "lexical choice continuation apply must accept exactly"
run_fixture "$repo_root/test/compile_fail/effect_optional_policy_missing_resume_or_return.zig" "optional policy must declare resumeOrReturn"
run_fixture "$repo_root/test/compile_fail/effect_optional_policy_wrong_after_resume_type.zig" "optional policy afterResume must have type"
run_fixture "$repo_root/test/compile_fail/algebraic_missing_handler.zig" "expects one spec per op"
run_fixture "$repo_root/test/compile_fail/algebraic_wrong_builder_mode.zig" "matching op mode"
run_fixture "$repo_root/test/compile_fail/algebraic_wrong_after_resume_type.zig" "afterResume must have type"
run_fixture "$repo_root/test/compile_fail/algebraic_undeclared_op.zig" "does not include the requested op"
run_fixture "$repo_root/test/compile_fail/effect_resource_context_removed.zig" "Context"
run_fixture "$repo_root/test/compile_fail/effect_resource_cross_instance_context_fails.zig" "context capability does not match supplied capability"
run_fixture "$repo_root/test/compile_fail/effect_resource_forged_context_acquire_fails.zig" "expected exact shift.effect context type"
run_fixture "$repo_root/test/compile_fail/effect_resource_acquire_without_context.zig" "expected a pointer to a shift.effect context"
run_fixture "$repo_root/test/compile_fail/effect_resource_manager_missing_acquire.zig" "resource manager must declare acquire"
run_fixture "$repo_root/test/compile_fail/effect_resource_manager_missing_release.zig" "resource manager must declare release"
run_fixture "$repo_root/test/compile_fail/effect_resource_manager_wrong_release_type.zig" "resource manager release must have type"
run_fixture "$repo_root/test/compile_fail/effect_writer_context_removed.zig" "Context"
run_fixture "$repo_root/test/compile_fail/effect_writer_cross_instance_context_fails.zig" "context capability does not match supplied capability"
run_fixture "$repo_root/test/compile_fail/effect_writer_forged_context_tell_fails.zig" "expected exact shift.effect context type"
run_fixture "$repo_root/test/compile_fail/effect_writer_tell_without_context.zig" "expected a pointer to a shift.effect context"
run_fixture "$repo_root/test/compile_fail/effect_define_missing_context_fails.zig" "expected a pointer to a shift.effect context"
run_fixture "$repo_root/test/compile_fail/effect_define_forged_context_fails.zig" "expected exact shift.effect context type"
run_fixture "$repo_root/test/compile_fail/effect_define_cross_instance_context_fails.zig" "context capability does not match supplied capability"
run_fixture "$repo_root/test/compile_fail/effect_define_duplicate_op_name_fails.zig" "generated effect op names must be unique"
run_fixture "$repo_root/test/compile_fail/effect_define_explicit_mode_mismatch_fails.zig" "generated effect explicit mode must match inferred op mode"
run_fixture "$repo_root/test/compile_fail/effect_define_reserved_name_fails.zig" "generated effect op name collides with reserved family export"
run_fixture "$repo_root/test/compile_fail/effect_define_missing_after_hook_fails.zig" "generated transform handler is missing after_<op> method"
run_fixture "$repo_root/test/compile_fail/effect_define_choice_wrong_hook_type_fails.zig" "generated choice handler op method must have type"
run_fixture "$repo_root/test/compile_fail/effect_define_lexical_choice_tag_dispatch_removed.zig" "no field or member function named 'perform'"
run_fixture "$repo_root/test/compile_fail/effect_define_lexical_abort_tag_dispatch_removed.zig" "no field or member function named 'abort'"
run_fixture "$repo_root/test/compile_fail/effect_define_mixed_mode_fails.zig" "generated effect families support one prompt mode per family"
run_fixture "$repo_root/test/compile_fail/root_reset_requires_program.zig" "expected type 'frontend.Program"
run_fixture "$repo_root/test/compile_fail/no_shift_guard_removed.zig" "NoShiftGuard"
run_fixture "$repo_root/test/compile_fail/resume_value_mismatch.zig" "must have type"
