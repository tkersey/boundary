#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
artifact_path="$repo_root/bench/baselines/state_effect_v1.json"
mode="${1:-}"

usage() {
  echo "usage: sh bench/state_effect_artifact.sh <write|check>" >&2
  exit 1
}

[ -n "$mode" ] || usage

case "$mode" in
  write|check) ;;
  *) usage ;;
esac

current_repo_state() {
  if git -C "$repo_root" diff --quiet --ignore-submodules HEAD -- . ':(exclude)bench/baselines/state_effect_v1.json' ':(exclude)bench/baselines/effect_family_matrix_v2.json' &&
    git -C "$repo_root" diff --quiet --ignore-submodules --cached -- . ':(exclude)bench/baselines/state_effect_v1.json' ':(exclude)bench/baselines/effect_family_matrix_v2.json'; then
    printf "clean"
  else
    printf "dirty"
  fi
}

repo_state="$(current_repo_state)"
allow_dirty="${SHIFT_ALLOW_DIRTY_ARTIFACT:-0}"

if [ "$repo_state" != "clean" ] && [ "$allow_dirty" != "1" ]; then
  echo "refusing to operate on dirty tree; set SHIFT_ALLOW_DIRTY_ARTIFACT=1 to override" >&2
  exit 1
fi

extract_scalar() {
  line="$1"
  key="$2"
  value="$(printf '%s\n' "$line" | sed -nE "s/.*${key}=([^ ]+).*/\\1/p")"
  [ -n "$value" ] || {
    echo "failed to parse scalar '$key' from benchmark output" >&2
    exit 1
  }
  printf '%s' "$value"
}

artifact_matches_current_tree() {
  artifact_git_rev="$1"
  current_git_rev="$2"

  if [ "$artifact_git_rev" = "$current_git_rev" ]; then
    return 0
  fi

  git -C "$repo_root" diff --quiet "$artifact_git_rev" "$current_git_rev" -- . ':(exclude)bench/baselines/state_effect_v1.json' ':(exclude)bench/baselines/effect_family_matrix_v2.json'
}

extract_array() {
  line="$1"
  key="$2"
  value="$(printf '%s\n' "$line" | sed -nE "s/.*${key}=\\[([^]]+)\\].*/[\\1]/p")"
  [ -n "$value" ] || {
    echo "failed to parse array '$key' from benchmark output" >&2
    exit 1
  }
  printf '%s' "$value"
}

json_scalar() {
  file="$1"
  key="$2"
  value="$(sed -nE "s/.*\"${key}\": \"([^\"]+)\".*/\\1/p" "$file" | head -n 1)"
  [ -n "$value" ] || {
    echo "missing JSON string field '$key' in $file" >&2
    exit 1
  }
  printf '%s' "$value"
}

json_number() {
  file="$1"
  key="$2"
  value="$(sed -nE "s/.*\"${key}\": ([0-9.]+).*/\\1/p" "$file" | head -n 1)"
  [ -n "$value" ] || {
    echo "missing JSON numeric field '$key' in $file" >&2
    exit 1
  }
  printf '%s' "$value"
}

json_section_number() {
  file="$1"
  section="$2"
  key="$3"
  value="$(
    sed -n "/\"${section}\": {/,/^[[:space:]]*}/p" "$file" |
      sed -nE "s/.*\"${key}\": ([0-9.]+).*/\\1/p" |
      head -n 1
  )"
  [ -n "$value" ] || {
    echo "missing JSON field '$key' in section '$section' of $file" >&2
    exit 1
  }
  printf '%s' "$value"
}

cpu_name() {
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n machdep.cpu.brand_string 2>/dev/null && return 0
  fi
  uname -m
}

run_bench() {
  (cd "$repo_root" && zig build bench-state-effect)
}

parse_bench_output() {
  bench_output="$1"

  summary_line="$(printf '%s\n' "$bench_output" | sed -n '1p')"
  raw_line="$(printf '%s\n' "$bench_output" | sed -n '2p')"
  raw_reset_only_line="$(printf '%s\n' "$bench_output" | sed -n '3p')"
  effect_line="$(printf '%s\n' "$bench_output" | sed -n '4p')"
  effect_passthrough_line="$(printf '%s\n' "$bench_output" | sed -n '5p')"

  [ -n "$effect_passthrough_line" ] || {
    echo "unexpected benchmark output shape" >&2
    printf '%s\n' "$bench_output" >&2
    exit 1
  }

  timed_iterations="$(extract_scalar "$summary_line" "timed_iterations")"
  warmup_iterations="$(extract_scalar "$summary_line" "warmup_iterations")"
  samples_per_run="$(extract_scalar "$summary_line" "samples_per_run")"
  raw_checksum="$(extract_scalar "$summary_line" "raw_checksum")"
  raw_reset_only_checksum="$(extract_scalar "$summary_line" "raw_reset_only_checksum")"
  effect_checksum="$(extract_scalar "$summary_line" "effect_checksum")"
  effect_passthrough_checksum="$(extract_scalar "$summary_line" "effect_passthrough_checksum")"

  raw_sample_ns="$(extract_array "$raw_line" "raw_sample_ns")"
  raw_min_ns="$(extract_scalar "$raw_line" "raw_min_ns")"
  raw_median_ns="$(extract_scalar "$raw_line" "raw_median_ns")"
  raw_max_ns="$(extract_scalar "$raw_line" "raw_max_ns")"

  raw_reset_only_sample_ns="$(extract_array "$raw_reset_only_line" "raw_reset_only_sample_ns")"
  raw_reset_only_min_ns="$(extract_scalar "$raw_reset_only_line" "raw_reset_only_min_ns")"
  raw_reset_only_median_ns="$(extract_scalar "$raw_reset_only_line" "raw_reset_only_median_ns")"
  raw_reset_only_max_ns="$(extract_scalar "$raw_reset_only_line" "raw_reset_only_max_ns")"

  effect_sample_ns="$(extract_array "$effect_line" "effect_sample_ns")"
  effect_min_ns="$(extract_scalar "$effect_line" "effect_min_ns")"
  effect_median_ns="$(extract_scalar "$effect_line" "effect_median_ns")"
  effect_max_ns="$(extract_scalar "$effect_line" "effect_max_ns")"

  effect_passthrough_sample_ns="$(extract_array "$effect_passthrough_line" "effect_passthrough_sample_ns")"
  effect_passthrough_min_ns="$(extract_scalar "$effect_passthrough_line" "effect_passthrough_min_ns")"
  effect_passthrough_median_ns="$(extract_scalar "$effect_passthrough_line" "effect_passthrough_median_ns")"
  effect_passthrough_max_ns="$(extract_scalar "$effect_passthrough_line" "effect_passthrough_max_ns")"

  observed_ratio="$(awk -v raw="$raw_median_ns" -v effect="$effect_median_ns" 'BEGIN { printf "%.16f", effect / raw }')"
}

write_artifact() {
  bench_output="$(run_bench)"
  parse_bench_output "$bench_output"

  git_rev="$(git -C "$repo_root" rev-parse HEAD)"
  captured_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  zig_version="$(zig version)"
  uname_value="$(uname -a)"
  cpu_value="$(cpu_name)"

  cat >"$artifact_path" <<EOF
{
  "artifact_schema_version": 2,
  "label": "state_effect_v1",
  "captured_at": "$captured_at",
  "git_rev": "$git_rev",
  "repo_state": "$repo_state",
  "host": {
    "uname": "$uname_value",
    "cpu": "$cpu_value",
    "zig_version": "$zig_version"
  },
  "measurement_contract": {
    "command": "zig build bench-state-effect",
    "timed_iterations": $timed_iterations,
    "warmup_iterations": $warmup_iterations,
    "samples_per_run": $samples_per_run,
    "summary_stat": "median_ns from one warmed invocation",
    "target_ratio_max": 1.05
  },
  "benchmarks": {
    "raw_state": {
      "checksum": $raw_checksum,
      "sample_ns": $raw_sample_ns,
      "min_ns": $raw_min_ns,
      "median_ns": $raw_median_ns,
      "max_ns": $raw_max_ns
    },
    "effect_state": {
      "checksum": $effect_checksum,
      "sample_ns": $effect_sample_ns,
      "min_ns": $effect_min_ns,
      "median_ns": $effect_median_ns,
      "max_ns": $effect_max_ns
    },
    "raw_reset_only": {
      "checksum": $raw_reset_only_checksum,
      "sample_ns": $raw_reset_only_sample_ns,
      "min_ns": $raw_reset_only_min_ns,
      "median_ns": $raw_reset_only_median_ns,
      "max_ns": $raw_reset_only_max_ns
    },
    "effect_passthrough": {
      "checksum": $effect_passthrough_checksum,
      "sample_ns": $effect_passthrough_sample_ns,
      "min_ns": $effect_passthrough_min_ns,
      "median_ns": $effect_passthrough_median_ns,
      "max_ns": $effect_passthrough_max_ns
    }
  },
  "observed_ratio": $observed_ratio
}
EOF
}

check_artifact() {
  [ -f "$artifact_path" ] || {
    echo "missing artifact: $artifact_path" >&2
    exit 1
  }

  artifact_schema_version="$(json_number "$artifact_path" "artifact_schema_version")"
  artifact_git_rev="$(json_scalar "$artifact_path" "git_rev")"
  artifact_repo_state="$(json_scalar "$artifact_path" "repo_state")"
  artifact_command="$(json_scalar "$artifact_path" "command")"
  artifact_target_ratio="$(json_number "$artifact_path" "target_ratio_max")"

  [ "$artifact_schema_version" = "2" ] || {
    echo "unexpected artifact schema version: $artifact_schema_version" >&2
    exit 1
  }
  [ "$artifact_command" = "zig build bench-state-effect" ] || {
    echo "unexpected artifact command: $artifact_command" >&2
    exit 1
  }

  current_git_rev="$(git -C "$repo_root" rev-parse HEAD)"
  artifact_matches_current_tree "$artifact_git_rev" "$current_git_rev" || {
    echo "artifact git_rev drift: expected $current_git_rev or a tree differing only by bench/baselines/state_effect_v1.json, found $artifact_git_rev" >&2
    exit 1
  }
  [ "$artifact_repo_state" = "$repo_state" ] || {
    echo "artifact repo_state drift: expected $repo_state, found $artifact_repo_state" >&2
    exit 1
  }

  bench_output="$(run_bench)"
  parse_bench_output "$bench_output"

  [ "$(json_section_number "$artifact_path" "raw_state" "checksum")" = "$raw_checksum" ] || {
    echo "raw_state checksum drift" >&2
    exit 1
  }
  [ "$(json_section_number "$artifact_path" "effect_state" "checksum")" = "$effect_checksum" ] || {
    echo "effect_state checksum drift" >&2
    exit 1
  }
  [ "$(json_section_number "$artifact_path" "raw_reset_only" "checksum")" = "$raw_reset_only_checksum" ] || {
    echo "raw_reset_only checksum drift" >&2
    exit 1
  }
  [ "$(json_section_number "$artifact_path" "effect_passthrough" "checksum")" = "$effect_passthrough_checksum" ] || {
    echo "effect_passthrough checksum drift" >&2
    exit 1
  }

  awk -v observed="$observed_ratio" -v target="$artifact_target_ratio" 'BEGIN { exit !(observed <= target) }' || {
    echo "observed ratio $observed_ratio exceeds target $artifact_target_ratio" >&2
    exit 1
  }
}

case "$mode" in
  write) write_artifact ;;
  check) check_artifact ;;
esac
