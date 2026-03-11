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

run_expected_failure() {
  fixture="$1"
  label="$2"
  expected="$3"
  stderr_file="$(mktemp)"
  trap 'rm -f "$stderr_file"' EXIT INT TERM

  if compile_fixture "$fixture" > /dev/null 2>"$stderr_file"; then
    echo "expected compile failure for $label" >&2
    exit 1
  fi

  if ! grep -q "$expected" "$stderr_file"; then
    echo "missing expected marker '$expected' for $label" >&2
    cat "$stderr_file" >&2
    exit 1
  fi

  rm -f "$stderr_file"
  trap - EXIT INT TERM
  printf "%s\tcompile_fail\n" "$label"
}

run_expected_success "$repo_root/test/one_shot_survey/protocol_resume_transform_compiles.zig" "protocol_resume_transform"
run_expected_success "$repo_root/test/one_shot_survey/protocol_erroring_resume_transform_compiles.zig" "protocol_erroring_resume_transform"
run_expected_success "$repo_root/test/one_shot_survey/protocol_direct_return_compiles.zig" "protocol_direct_return"
run_expected_success "$repo_root/test/one_shot_survey/protocol_erroring_direct_return_compiles.zig" "protocol_erroring_direct_return"
run_expected_failure "$repo_root/test/one_shot_survey/missing_after_resume_fails.zig" "missing_after_resume" "must declare afterResume"
run_expected_failure "$repo_root/test/one_shot_survey/wrong_after_resume_type_fails.zig" "wrong_after_resume_type" "must have type"
run_expected_failure "$repo_root/test/one_shot_survey/direct_return_mode_mismatch_fails.zig" "direct_return_mode_mismatch" "must declare directReturn"
run_expected_failure "$repo_root/test/one_shot_survey/legacy_continuation_alias_recheck_fails.zig" "legacy_alias_recheck" "Continuation"
run_expected_failure "$repo_root/test/one_shot_survey/legacy_continuation_store_recheck_fails.zig" "legacy_store_recheck" "Continuation"
