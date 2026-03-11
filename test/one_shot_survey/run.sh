#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

case "$(uname -m)" in
  arm64|aarch64)
    asm_file="$repo_root/src/runtime/aarch64_switch.S"
    ;;
  x86_64|amd64)
    asm_file="$repo_root/src/runtime/x86_64_switch.S"
    ;;
  *)
    echo "unsupported host arch for one-shot survey: $(uname -m)" >&2
    exit 1
    ;;
esac

compile_fixture() {
  fixture="$1"
  zig build-obj \
    -ODebug \
    -fno-emit-bin \
    --dep shift \
    -Mroot="$fixture" \
    "$asm_file" \
    -Mshift="$repo_root/src/root.zig" \
    --cache-dir "$repo_root/.zig-cache" \
    --global-cache-dir "${HOME}/.cache/zig" \
    --name one-shot-survey-fixture
}

run_expected_success() {
  fixture="$1"
  label="$2"
  stderr_file="$(mktemp)"
  trap 'rm -f "$stderr_file"' EXIT INT TERM

  if ! compile_fixture "$fixture" > /dev/null 2>"$stderr_file"; then
    echo "expected compile success for $label" >&2
    cat "$stderr_file" >&2
    exit 1
  fi

  rm -f "$stderr_file"
  trap - EXIT INT TERM
  printf "%s\tcompile_success\n" "$label"
}

run_expected_success "$repo_root/test/one_shot_survey/alias_copy_compiles.zig" "alias_copy"
run_expected_success "$repo_root/test/one_shot_survey/store_escape_compiles.zig" "store_escape"
run_expected_success "$repo_root/test/one_shot_survey/typestate_consuming_value_compiles.zig" "typestate_value"
run_expected_success "$repo_root/test/one_shot_survey/consumed_state_wrapper_compiles.zig" "consumed_wrapper"
run_expected_success "$repo_root/test/one_shot_survey/prompt_owned_borrowed_token_compiles.zig" "borrowed_token"
run_expected_success "$repo_root/test/one_shot_survey/split_token_resume_compiles.zig" "split_token"
run_expected_success "$repo_root/test/one_shot_survey/opaque_state_capsule_compiles.zig" "opaque_capsule"
run_expected_success "$repo_root/test/one_shot_survey/comptime_generated_capability_compiles.zig" "comptime_capability"
