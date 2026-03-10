#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_path="${1:-$repo_root/bench/baselines/pending_owner_api_perf_proof_v2.json}"
repetitions="${REPETITIONS:-7}"

cd "$repo_root"

if [[ ! "$repetitions" =~ ^[0-9]+$ ]] || [ "$repetitions" -lt 1 ]; then
  echo "REPETITIONS must be a positive integer" >&2
  exit 2
fi

bench_file="$(mktemp)"
bench_first_file="$(mktemp)"
trap 'rm -f "$bench_file" "$bench_first_file"' EXIT

run_medians() {
  local command="$1"
  local output_file="$2"
  local i

  : >"$output_file"
  for i in $(seq 1 "$repetitions"); do
    local median
    median="$($command | sed -n 's/.*median_ns=\([0-9][0-9]*\).*/\1/p')"
    if [ -z "$median" ]; then
      echo "failed to parse median_ns from: $command" >&2
      exit 1
    fi
    printf '%s\n' "$median" >>"$output_file"
  done
}

run_medians "zig build bench" "$bench_file"
run_medians "zig build bench-first-suspend" "$bench_first_file"

join_numbers() {
  local file="$1"
  paste -sd, "$file"
}

median_of_file() {
  local file="$1"
  local count
  count="$(wc -l < "$file" | tr -d ' ')"
  local index=$(( (count + 1) / 2 ))
  sort -n "$file" | sed -n "${index}p"
}

delta_pct() {
  local baseline="$1"
  local candidate="$2"
  awk -v base="$baseline" -v cand="$candidate" 'BEGIN { printf "%.2f", ((cand - base) / base) * 100 }'
}

bench_target=3222042
bench_first_target=5481416
threshold_pct=5.0

bench_candidate="$(median_of_file "$bench_file")"
bench_first_candidate="$(median_of_file "$bench_first_file")"

bench_delta="$(delta_pct "$bench_target" "$bench_candidate")"
bench_first_delta="$(delta_pct "$bench_first_target" "$bench_first_candidate")"

bench_pass=true
bench_first_pass=true

if awk -v d="$bench_delta" 'BEGIN { exit !(d > 5.0 || d < -5.0) }'; then
  bench_pass=false
fi

if awk -v d="$bench_first_delta" 'BEGIN { exit !(d > 5.0 || d < -5.0) }'; then
  bench_first_pass=false
fi

captured_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
git_rev="$(git rev-parse --short HEAD)"
mkdir -p "$(dirname "$output_path")"

cat >"$output_path" <<EOF
{
  "label": "pending_owner_api_perf_proof_v2",
  "captured_at": "$captured_at",
  "comparison_target": {
    "artifact": "bench/baselines/direct_style_v2.json",
    "description": "warmed direct-style baseline before the pending-owner public API cut"
  },
  "candidate": {
    "git_rev": "$git_rev",
    "description": "repeated warmed invocations after the pending-owner public API cut"
  },
  "measurement_contract": {
    "command": "zig build bench / zig build bench-first-suspend",
    "timed_iterations": 50000,
    "warmup_iterations": 20000,
    "samples_per_run": 5,
    "repeated_invocations": $repetitions,
    "summary_stat": "p50 of warmed invocation medians",
    "same_machine": true
  },
  "results": {
    "bench": {
      "target_median_ns": $bench_target,
      "candidate_invocation_medians_ns": [$(join_numbers "$bench_file")],
      "candidate_p50_ns": $bench_candidate,
      "delta_pct": $bench_delta,
      "threshold_pct": $threshold_pct,
      "pass": $bench_pass
    },
    "bench_first_suspend": {
      "target_median_ns": $bench_first_target,
      "candidate_invocation_medians_ns": [$(join_numbers "$bench_first_file")],
      "candidate_p50_ns": $bench_first_candidate,
      "delta_pct": $bench_first_delta,
      "threshold_pct": $threshold_pct,
      "pass": $bench_first_pass
    }
  },
  "verdict": "Repeated warmed invocations are the source of truth for the pending-owner API follow-up; this replaces one-off regression judgment for noisy first-suspend measurements."
}
EOF

printf 'wrote %s\n' "$output_path"
