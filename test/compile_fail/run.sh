#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
cache_root="$(mktemp -d "${TMPDIR:-/tmp}/shift-compile-fail-cache.XXXXXX")"
local_cache_dir="$cache_root/local"
global_cache_dir="$cache_root/global"

mkdir -p "$local_cache_dir" "$global_cache_dir"
trap 'rm -rf "$cache_root"' EXIT INT TERM

case "$(uname -m)" in
  arm64|aarch64)
    asm_file="$repo_root/src/runtime/aarch64_switch.S"
    ;;
  x86_64|amd64)
    asm_file="$repo_root/src/runtime/x86_64_switch.S"
    ;;
  *)
    echo "unsupported host arch for compile-fail harness: $(uname -m)" >&2
    exit 1
    ;;
esac

run_fixture() {
  fixture="$1"
  expected="$2"
  stderr_file="$(mktemp)"

  if zig build-obj \
    -ODebug \
    -fno-emit-bin \
    --dep shift \
    -Mroot="$fixture" \
    "$asm_file" \
    -Mshift="$repo_root/src/root.zig" \
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
run_fixture "$repo_root/test/compile_fail/effect_optional_policy_missing_resume_or_return.zig" "optional policy must declare resumeOrReturn"
run_fixture "$repo_root/test/compile_fail/effect_optional_policy_wrong_after_resume_type.zig" "optional policy afterResume must have type"
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
run_fixture "$repo_root/test/compile_fail/no_shift_guard_removed.zig" "NoShiftGuard"
run_fixture "$repo_root/test/compile_fail/resume_value_mismatch.zig" "must have type"
