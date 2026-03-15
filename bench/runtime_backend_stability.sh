#!/usr/bin/env sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
runs="${SHIFT_RUNTIME_BACKEND_STABILITY_RUNS:-5}"

case "$runs" in
  ''|*[!0-9]*)
    echo "SHIFT_RUNTIME_BACKEND_STABILITY_RUNS must be a positive integer" >&2
    exit 1
    ;;
esac

[ "$runs" -gt 0 ] || {
  echo "SHIFT_RUNTIME_BACKEND_STABILITY_RUNS must be greater than zero" >&2
  exit 1
}

current_repo_state() {
  if git -C "$repo_root" diff --quiet --ignore-submodules HEAD -- . \
    ':(exclude)bench/baselines/state_effect_v1.json' \
    ':(exclude)bench/baselines/effect_family_matrix_v2.json' \
    ':(exclude)bench/baselines/runtime_backend_matrix_v1.json' &&
    git -C "$repo_root" diff --quiet --ignore-submodules --cached -- . \
    ':(exclude)bench/baselines/state_effect_v1.json' \
    ':(exclude)bench/baselines/effect_family_matrix_v2.json' \
    ':(exclude)bench/baselines/runtime_backend_matrix_v1.json'; then
    printf "clean"
  else
    printf "dirty"
  fi
}

repo_state="$(current_repo_state)"
[ "$repo_state" = "clean" ] || {
  echo "runtime-backend stability must run on a clean tree" >&2
  exit 1
}

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/shift-runtime-backend-stability.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

run_idx=1
while [ "$run_idx" -le "$runs" ]; do
  (cd "$repo_root" && zig build bench-runtime-backends) >"$tmpdir/run-$run_idx.txt"
  run_idx=$((run_idx + 1))
done

awk '
function classify(lane, status) {
  if (fail_count[lane] == 0) status = "stable_pass";
  else if (fail_count[lane] == run_count[lane]) status = "stable_fail";
  else status = "flaky";
  return status;
}

FNR == 1 { next; }

{
  lane = "";
  target = "";
  stack = "";
  lowered = "";
  for (i = 1; i <= NF; i += 1) {
    split($i, kv, "=");
    if (kv[1] == "lane") lane = kv[2];
    else if (kv[1] == "target_ratio_max") target = kv[2] + 0;
    else if (kv[1] == "stack_median_ns") stack = kv[2] + 0;
    else if (kv[1] == "lowered_median_ns") lowered = kv[2] + 0;
  }
  if (lane == "" || stack == 0) next;

  ratio = lowered / stack;
  status = (ratio > target) ? 1 : 0;

  if (!(lane in seen)) {
    order[++order_count] = lane;
    seen[lane] = 1;
    min_ratio[lane] = ratio;
    max_ratio[lane] = ratio;
    fail_count[lane] = 0;
    run_count[lane] = 0;
    target_ratio[lane] = target;
  }

  if (ratio < min_ratio[lane]) min_ratio[lane] = ratio;
  if (ratio > max_ratio[lane]) max_ratio[lane] = ratio;
  fail_count[lane] += status;
  run_count[lane] += 1;
}

END {
  unstable = 0;
  for (idx = 1; idx <= order_count; idx += 1) {
    lane = order[idx];
    lane_status = classify(lane);
    printf "%s\tstatus=%s\tfail_runs=%d/%d\ttarget=%.2f\tmin_ratio=%.6f\tmax_ratio=%.6f\n",
      lane, lane_status, fail_count[lane], run_count[lane], target_ratio[lane], min_ratio[lane], max_ratio[lane];
    if (lane_status != "stable_pass") unstable = 1;
  }
  exit unstable;
}
' "$tmpdir"/run-*.txt
