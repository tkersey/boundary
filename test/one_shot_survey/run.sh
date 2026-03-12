#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
survey_dir="$repo_root/test/one_shot_survey"
cache_root="$(mktemp -d "${TMPDIR:-/tmp}/shift-one-shot-survey-cache.XXXXXX")"
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
    --cache-dir "$local_cache_dir" \
    --global-cache-dir "$global_cache_dir" \
    --name one-shot-survey-fixture
}

fixture_rows() {
  cat <<'EOF'
protocol_resume_transform_compiles.zig|success|protocol_resume_transform|
protocol_erroring_resume_transform_compiles.zig|success|protocol_erroring_resume_transform|
protocol_direct_return_compiles.zig|success|protocol_direct_return|
protocol_erroring_direct_return_compiles.zig|success|protocol_erroring_direct_return|
protocol_resume_or_return_compiles.zig|success|protocol_resume_or_return|
protocol_erroring_resume_or_return_compiles.zig|success|protocol_erroring_resume_or_return|
missing_after_resume_fails.zig|failure|missing_after_resume|must declare afterResume
missing_resume_or_return_fails.zig|failure|missing_resume_or_return|must declare resumeOrReturn
wrong_after_resume_type_fails.zig|failure|wrong_after_resume_type|must have type
wrong_resume_or_return_type_fails.zig|failure|wrong_resume_or_return_type|must have type
wrong_resume_or_return_after_resume_fails.zig|failure|wrong_resume_or_return_after_resume|must have type
direct_return_mode_mismatch_fails.zig|failure|direct_return_mode_mismatch|must declare directReturn
legacy_continuation_alias_recheck_fails.zig|failure|legacy_alias_recheck|Continuation
legacy_continuation_store_recheck_fails.zig|failure|legacy_store_recheck|Continuation
EOF
}

check_fixture_classification() {
  actual_file="$(mktemp)"
  classified_file="$(mktemp)"

  find "$survey_dir" -maxdepth 1 -type f -name '*.zig' -exec basename {} \; | sort >"$actual_file"
  fixture_rows | while IFS='|' read -r fixture_name _ _ _; do
    [ -n "$fixture_name" ] || continue
    printf '%s\n' "$fixture_name"
  done | sort >"$classified_file"

  if ! diff -u "$classified_file" "$actual_file" >/dev/null; then
    echo "one-shot survey fixture set is out of sync with run.sh classifications" >&2
    diff -u "$classified_file" "$actual_file" >&2 || true
    rm -f "$actual_file" "$classified_file"
    exit 1
  fi

  rm -f "$actual_file" "$classified_file"
}

run_expected_success() {
  fixture="$1"
  label="$2"
  stderr_file="$(mktemp)"

  if ! compile_fixture "$fixture" > /dev/null 2>"$stderr_file"; then
    echo "expected compile success for $label" >&2
    cat "$stderr_file" >&2
    rm -f "$stderr_file"
    exit 1
  fi

  rm -f "$stderr_file"
  printf "%s\tcompile_success\n" "$label"
}

run_expected_failure() {
  fixture="$1"
  label="$2"
  expected="$3"
  stderr_file="$(mktemp)"

  if compile_fixture "$fixture" > /dev/null 2>"$stderr_file"; then
    echo "expected compile failure for $label" >&2
    rm -f "$stderr_file"
    exit 1
  fi

  if ! grep -q "$expected" "$stderr_file"; then
    echo "missing expected marker '$expected' for $label" >&2
    cat "$stderr_file" >&2
    rm -f "$stderr_file"
    exit 1
  fi

  rm -f "$stderr_file"
  printf "%s\tcompile_fail\n" "$label"
}

check_fixture_classification

while IFS='|' read -r fixture_name mode label expected; do
  [ -n "$fixture_name" ] || continue

  fixture_path="$survey_dir/$fixture_name"
  if [ ! -f "$fixture_path" ]; then
    echo "missing classified one-shot survey fixture: $fixture_name" >&2
    exit 1
  fi

  case "$mode" in
    success)
      run_expected_success "$fixture_path" "$label"
      ;;
    failure)
      run_expected_failure "$fixture_path" "$label" "$expected"
      ;;
    *)
      echo "unknown survey classification mode '$mode' for $fixture_name" >&2
      exit 1
      ;;
  esac
done <<EOF
$(fixture_rows)
EOF
