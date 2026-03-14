#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
artifact_path="$repo_root/bench/baselines/effect_family_matrix_v2.json"
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

  git -C "$repo_root" diff --quiet "$artifact_git_rev" "$current_git_rev" -- . ':(exclude)bench/baselines/effect_family_matrix_v2.json'
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

lane_names="state_micro reader_micro reader_batch8 optional_return_now_micro optional_return_now_prelude8 optional_resume_with_micro optional_resume_with_batch8 exception_throw_micro exception_throw_prelude8 resource_normal_4 resource_normal_32 writer_micro writer_batch16 writer_batch64"

parse_lane_line() {
  line="$1"
  lane="$(extract_scalar "$line" "lane")"
  raw_median_ns="$(extract_scalar "$line" "raw_median_ns")"
  effect_median_ns="$(extract_scalar "$line" "effect_median_ns")"
  observed_ratio="$(awk -v raw="$raw_median_ns" -v effect="$effect_median_ns" 'BEGIN { printf "%.16f", effect / raw }')"

  eval "${lane}_lane_class='$(extract_scalar "$line" "lane_class")'"
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
  schema_version="$(extract_scalar "$summary_line" "schema_version")"
  timed_iterations="$(extract_scalar "$summary_line" "timed_iterations")"
  warmup_iterations="$(extract_scalar "$summary_line" "warmup_iterations")"
  samples_per_run="$(extract_scalar "$summary_line" "samples_per_run")"

  [ "$lane_count" = "14" ] || {
    echo "unexpected lane count: $lane_count" >&2
    exit 1
  }
  [ "$schema_version" = "2" ] || {
    echo "unexpected schema version: $schema_version" >&2
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

  {
    printf '{\n'
    printf '  "artifact_schema_version": 2,\n'
    printf '  "label": "effect_family_matrix_v2",\n'
    printf '  "captured_at": "%s",\n' "$captured_at"
    printf '  "git_rev": "%s",\n' "$git_rev"
    printf '  "repo_state": "%s",\n' "$repo_state"
    printf '  "host": {\n'
    printf '    "uname": "%s",\n' "$uname_value"
    printf '    "cpu": "%s",\n' "$cpu_value"
    printf '    "zig_version": "%s"\n' "$zig_version"
    printf '  },\n'
    printf '  "measurement_contract": {\n'
    printf '    "command": "zig build bench-effect-matrix",\n'
    printf '    "timed_iterations": %s,\n' "$timed_iterations"
    printf '    "warmup_iterations": %s,\n' "$warmup_iterations"
    printf '    "samples_per_run": %s,\n' "$samples_per_run"
    printf '    "summary_stat": "median_ns from one warmed invocation"\n'
    printf '  },\n'
    printf '  "covered_families": ["state","reader","optional","exception","resource","writer"],\n'
    printf '  "lane_classes": ["micro","amortized","investigation"],\n'
    printf '  "uncovered_paths": ["resource_abortive_cleanup"],\n'
    printf '  "lanes": {\n'

    first=1
    for lane in $lane_names; do
      eval "lane_class=\${${lane}_lane_class}"
      eval "target_ratio_max=\${${lane}_target_ratio_max}"
      eval "raw_checksum=\${${lane}_raw_checksum}"
      eval "effect_checksum=\${${lane}_effect_checksum}"
      eval "raw_sample_ns=\${${lane}_raw_sample_ns}"
      eval "effect_sample_ns=\${${lane}_effect_sample_ns}"
      eval "raw_min_ns=\${${lane}_raw_min_ns}"
      eval "raw_median_ns=\${${lane}_raw_median_ns}"
      eval "raw_max_ns=\${${lane}_raw_max_ns}"
      eval "effect_min_ns=\${${lane}_effect_min_ns}"
      eval "effect_median_ns=\${${lane}_effect_median_ns}"
      eval "effect_max_ns=\${${lane}_effect_max_ns}"
      eval "observed_ratio=\${${lane}_observed_ratio}"

      if [ "$first" -eq 0 ]; then
        printf ',\n'
      fi
      first=0

      printf '    "%s": {\n' "$lane"
      printf '      "lane_class": "%s",\n' "$lane_class"
      printf '      "target_ratio_max": %s,\n' "$target_ratio_max"
      printf '      "raw_checksum": %s,\n' "$raw_checksum"
      printf '      "effect_checksum": %s,\n' "$effect_checksum"
      printf '      "raw_sample_ns": %s,\n' "$raw_sample_ns"
      printf '      "effect_sample_ns": %s,\n' "$effect_sample_ns"
      printf '      "raw_min_ns": %s,\n' "$raw_min_ns"
      printf '      "raw_median_ns": %s,\n' "$raw_median_ns"
      printf '      "raw_max_ns": %s,\n' "$raw_max_ns"
      printf '      "effect_min_ns": %s,\n' "$effect_min_ns"
      printf '      "effect_median_ns": %s,\n' "$effect_median_ns"
      printf '      "effect_max_ns": %s,\n' "$effect_max_ns"
      printf '      "observed_ratio": %s\n' "$observed_ratio"
      printf '    }'
    done

    printf '\n  }\n'
    printf '}\n'
  } >"$artifact_path"
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
  grep -q '"lane_classes": \["micro","amortized","investigation"\]' "$artifact_path" || {
    echo "lane_classes drift" >&2
    exit 1
  }
  grep -q '"uncovered_paths": \["resource_abortive_cleanup"\]' "$artifact_path" || {
    echo "uncovered_paths drift" >&2
    exit 1
  }

  [ "$artifact_schema_version" = "2" ] || {
    echo "unexpected artifact schema version: $artifact_schema_version" >&2
    exit 1
  }
  [ "$artifact_command" = "zig build bench-effect-matrix" ] || {
    echo "unexpected artifact command: $artifact_command" >&2
    exit 1
  }

  current_git_rev="$(git -C "$repo_root" rev-parse HEAD)"
  artifact_matches_current_tree "$artifact_git_rev" "$current_git_rev" || {
    echo "artifact git_rev drift: expected $current_git_rev or a tree differing only by bench/baselines/effect_family_matrix_v2.json, found $artifact_git_rev" >&2
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
