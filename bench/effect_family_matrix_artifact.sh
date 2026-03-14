#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
artifact_path="$repo_root/bench/baselines/effect_family_matrix_v1.json"
mode="${1:-}"

usage() {
  echo "usage: sh bench/effect_family_matrix_artifact.sh <write|check>" >&2
  exit 1
}

[ -n "$mode" ] || usage

case "$mode" in
  write|check) ;;
  *) usage ;;
esac

current_repo_state() {
  if git -C "$repo_root" diff --quiet --ignore-submodules HEAD -- && git -C "$repo_root" diff --quiet --ignore-submodules --cached --; then
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

artifact_matches_current_tree() {
  artifact_git_rev="$1"
  current_git_rev="$2"

  if [ "$artifact_git_rev" = "$current_git_rev" ]; then
    return 0
  fi

  git -C "$repo_root" diff --quiet "$artifact_git_rev" "$current_git_rev" -- . ':(exclude)bench/baselines/effect_family_matrix_v1.json'
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

json_lane_number() {
  file="$1"
  lane="$2"
  key="$3"
  value="$(
    sed -n "/\"${lane}\": {/,/^[[:space:]]*}/p" "$file" |
      sed -nE "s/.*\"${key}\": ([0-9.]+).*/\\1/p" |
      head -n 1
  )"
  [ -n "$value" ] || {
    echo "missing JSON field '$key' for lane '$lane' in $file" >&2
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
  (cd "$repo_root" && zig build bench-effect-matrix)
}

lane_names="state reader optional_return_now optional_resume_with exception_throw resource_normal writer"

parse_lane_line() {
  line="$1"
  lane="$(extract_scalar "$line" "lane")"
  raw_median_ns="$(extract_scalar "$line" "raw_median_ns")"
  effect_median_ns="$(extract_scalar "$line" "effect_median_ns")"
  observed_ratio="$(awk -v raw="$raw_median_ns" -v effect="$effect_median_ns" 'BEGIN { printf "%.16f", effect / raw }')"

  eval "${lane}_target_ratio_max='$(extract_scalar "$line" "target_ratio_max")'"
  eval "${lane}_raw_checksum='$(extract_scalar "$line" "raw_checksum")'"
  eval "${lane}_effect_checksum='$(extract_scalar "$line" "effect_checksum")'"
  eval "${lane}_raw_sample_ns='$(extract_array "$line" "raw_sample_ns")'"
  eval "${lane}_effect_sample_ns='$(extract_array "$line" "effect_sample_ns")'"
  eval "${lane}_raw_min_ns='$(extract_scalar "$line" "raw_min_ns")'"
  eval "${lane}_raw_median_ns='$raw_median_ns'"
  eval "${lane}_raw_max_ns='$(extract_scalar "$line" "raw_max_ns")'"
  eval "${lane}_effect_min_ns='$(extract_scalar "$line" "effect_min_ns")'"
  eval "${lane}_effect_median_ns='$effect_median_ns'"
  eval "${lane}_effect_max_ns='$(extract_scalar "$line" "effect_max_ns")'"
  eval "${lane}_observed_ratio='$observed_ratio'"
}

parse_bench_output() {
  bench_output="$1"
  summary_line="$(printf '%s\n' "$bench_output" | sed -n '1p')"
  lane_count="$(extract_scalar "$summary_line" "lanes")"
  timed_iterations="$(extract_scalar "$summary_line" "timed_iterations")"
  warmup_iterations="$(extract_scalar "$summary_line" "warmup_iterations")"
  samples_per_run="$(extract_scalar "$summary_line" "samples_per_run")"

  [ "$lane_count" = "7" ] || {
    echo "unexpected lane count: $lane_count" >&2
    exit 1
  }

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    parse_lane_line "$line"
  done <<EOF
$(printf '%s\n' "$bench_output" | sed -n '2,$p')
EOF

  for lane in $lane_names; do
    eval "value=\${${lane}_effect_median_ns:-}"
    [ -n "$value" ] || {
      echo "missing parsed lane output for $lane" >&2
      exit 1
    }
  done
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
  "artifact_schema_version": 1,
  "label": "effect_family_matrix_v1",
  "captured_at": "$captured_at",
  "git_rev": "$git_rev",
  "repo_state": "$repo_state",
  "host": {
    "uname": "$uname_value",
    "cpu": "$cpu_value",
    "zig_version": "$zig_version"
  },
  "measurement_contract": {
    "command": "zig build bench-effect-matrix",
    "timed_iterations": $timed_iterations,
    "warmup_iterations": $warmup_iterations,
    "samples_per_run": $samples_per_run,
    "summary_stat": "median_ns from one warmed invocation"
  },
  "covered_families": ["state","reader","optional","exception","resource","writer"],
  "uncovered_paths": ["resource_abortive_cleanup"],
  "lanes": {
    "state": {
      "target_ratio_max": $state_target_ratio_max,
      "raw_checksum": $state_raw_checksum,
      "effect_checksum": $state_effect_checksum,
      "raw_sample_ns": $state_raw_sample_ns,
      "effect_sample_ns": $state_effect_sample_ns,
      "raw_min_ns": $state_raw_min_ns,
      "raw_median_ns": $state_raw_median_ns,
      "raw_max_ns": $state_raw_max_ns,
      "effect_min_ns": $state_effect_min_ns,
      "effect_median_ns": $state_effect_median_ns,
      "effect_max_ns": $state_effect_max_ns,
      "observed_ratio": $state_observed_ratio
    },
    "reader": {
      "target_ratio_max": $reader_target_ratio_max,
      "raw_checksum": $reader_raw_checksum,
      "effect_checksum": $reader_effect_checksum,
      "raw_sample_ns": $reader_raw_sample_ns,
      "effect_sample_ns": $reader_effect_sample_ns,
      "raw_min_ns": $reader_raw_min_ns,
      "raw_median_ns": $reader_raw_median_ns,
      "raw_max_ns": $reader_raw_max_ns,
      "effect_min_ns": $reader_effect_min_ns,
      "effect_median_ns": $reader_effect_median_ns,
      "effect_max_ns": $reader_effect_max_ns,
      "observed_ratio": $reader_observed_ratio
    },
    "optional_return_now": {
      "target_ratio_max": $optional_return_now_target_ratio_max,
      "raw_checksum": $optional_return_now_raw_checksum,
      "effect_checksum": $optional_return_now_effect_checksum,
      "raw_sample_ns": $optional_return_now_raw_sample_ns,
      "effect_sample_ns": $optional_return_now_effect_sample_ns,
      "raw_min_ns": $optional_return_now_raw_min_ns,
      "raw_median_ns": $optional_return_now_raw_median_ns,
      "raw_max_ns": $optional_return_now_raw_max_ns,
      "effect_min_ns": $optional_return_now_effect_min_ns,
      "effect_median_ns": $optional_return_now_effect_median_ns,
      "effect_max_ns": $optional_return_now_effect_max_ns,
      "observed_ratio": $optional_return_now_observed_ratio
    },
    "optional_resume_with": {
      "target_ratio_max": $optional_resume_with_target_ratio_max,
      "raw_checksum": $optional_resume_with_raw_checksum,
      "effect_checksum": $optional_resume_with_effect_checksum,
      "raw_sample_ns": $optional_resume_with_raw_sample_ns,
      "effect_sample_ns": $optional_resume_with_effect_sample_ns,
      "raw_min_ns": $optional_resume_with_raw_min_ns,
      "raw_median_ns": $optional_resume_with_raw_median_ns,
      "raw_max_ns": $optional_resume_with_raw_max_ns,
      "effect_min_ns": $optional_resume_with_effect_min_ns,
      "effect_median_ns": $optional_resume_with_effect_median_ns,
      "effect_max_ns": $optional_resume_with_effect_max_ns,
      "observed_ratio": $optional_resume_with_observed_ratio
    },
    "exception_throw": {
      "target_ratio_max": $exception_throw_target_ratio_max,
      "raw_checksum": $exception_throw_raw_checksum,
      "effect_checksum": $exception_throw_effect_checksum,
      "raw_sample_ns": $exception_throw_raw_sample_ns,
      "effect_sample_ns": $exception_throw_effect_sample_ns,
      "raw_min_ns": $exception_throw_raw_min_ns,
      "raw_median_ns": $exception_throw_raw_median_ns,
      "raw_max_ns": $exception_throw_raw_max_ns,
      "effect_min_ns": $exception_throw_effect_min_ns,
      "effect_median_ns": $exception_throw_effect_median_ns,
      "effect_max_ns": $exception_throw_effect_max_ns,
      "observed_ratio": $exception_throw_observed_ratio
    },
    "resource_normal": {
      "target_ratio_max": $resource_normal_target_ratio_max,
      "raw_checksum": $resource_normal_raw_checksum,
      "effect_checksum": $resource_normal_effect_checksum,
      "raw_sample_ns": $resource_normal_raw_sample_ns,
      "effect_sample_ns": $resource_normal_effect_sample_ns,
      "raw_min_ns": $resource_normal_raw_min_ns,
      "raw_median_ns": $resource_normal_raw_median_ns,
      "raw_max_ns": $resource_normal_raw_max_ns,
      "effect_min_ns": $resource_normal_effect_min_ns,
      "effect_median_ns": $resource_normal_effect_median_ns,
      "effect_max_ns": $resource_normal_effect_max_ns,
      "observed_ratio": $resource_normal_observed_ratio
    },
    "writer": {
      "target_ratio_max": $writer_target_ratio_max,
      "raw_checksum": $writer_raw_checksum,
      "effect_checksum": $writer_effect_checksum,
      "raw_sample_ns": $writer_raw_sample_ns,
      "effect_sample_ns": $writer_effect_sample_ns,
      "raw_min_ns": $writer_raw_min_ns,
      "raw_median_ns": $writer_raw_median_ns,
      "raw_max_ns": $writer_raw_max_ns,
      "effect_min_ns": $writer_effect_min_ns,
      "effect_median_ns": $writer_effect_median_ns,
      "effect_max_ns": $writer_effect_max_ns,
      "observed_ratio": $writer_observed_ratio
    }
  }
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

  grep -q '"covered_families": \["state","reader","optional","exception","resource","writer"\]' "$artifact_path" || {
    echo "covered_families drift" >&2
    exit 1
  }
  grep -q '"uncovered_paths": \["resource_abortive_cleanup"\]' "$artifact_path" || {
    echo "uncovered_paths drift" >&2
    exit 1
  }

  [ "$artifact_schema_version" = "1" ] || {
    echo "unexpected artifact schema version: $artifact_schema_version" >&2
    exit 1
  }
  [ "$artifact_command" = "zig build bench-effect-matrix" ] || {
    echo "unexpected artifact command: $artifact_command" >&2
    exit 1
  }

  current_git_rev="$(git -C "$repo_root" rev-parse HEAD)"
  artifact_matches_current_tree "$artifact_git_rev" "$current_git_rev" || {
    echo "artifact git_rev drift: expected $current_git_rev or a tree differing only by bench/baselines/effect_family_matrix_v1.json, found $artifact_git_rev" >&2
    exit 1
  }
  [ "$artifact_repo_state" = "$repo_state" ] || {
    echo "artifact repo_state drift: expected $repo_state, found $artifact_repo_state" >&2
    exit 1
  }

  bench_output="$(run_bench)"
  parse_bench_output "$bench_output"

  for lane in $lane_names; do
    eval "artifact_raw_checksum=\$(json_lane_number \"$artifact_path\" \"$lane\" \"raw_checksum\")"
    eval "artifact_effect_checksum=\$(json_lane_number \"$artifact_path\" \"$lane\" \"effect_checksum\")"
    eval "artifact_target_ratio=\$(json_lane_number \"$artifact_path\" \"$lane\" \"target_ratio_max\")"
    eval "artifact_observed_ratio=\$(json_lane_number \"$artifact_path\" \"$lane\" \"observed_ratio\")"
    eval "live_raw_checksum=\${${lane}_raw_checksum}"
    eval "live_effect_checksum=\${${lane}_effect_checksum}"
    eval "live_observed_ratio=\${${lane}_observed_ratio}"

    [ "$artifact_raw_checksum" = "$live_raw_checksum" ] || {
      echo "$lane raw checksum drift" >&2
      exit 1
    }
    [ "$artifact_effect_checksum" = "$live_effect_checksum" ] || {
      echo "$lane effect checksum drift" >&2
      exit 1
    }
    awk -v observed="$live_observed_ratio" -v target="$artifact_target_ratio" 'BEGIN { exit !(observed <= target) }' || {
      echo "$lane observed ratio $live_observed_ratio exceeds target $artifact_target_ratio" >&2
      exit 1
    }
    awk -v observed="$artifact_observed_ratio" -v target="$artifact_target_ratio" 'BEGIN { exit !(observed <= target) }' || {
      echo "$lane recorded ratio $artifact_observed_ratio exceeds target $artifact_target_ratio" >&2
      exit 1
    }
  done
}

case "$mode" in
  write) write_artifact ;;
  check) check_artifact ;;
esac
