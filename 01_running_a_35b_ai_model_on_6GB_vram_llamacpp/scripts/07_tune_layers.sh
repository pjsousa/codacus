#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_runtime

read -r -a MOE_VALUES <<<"${MOE_VALUES:-40 38 36 35 34 32}"
run_group="layer_tune_$(timestamp)"
group_dir="$RESULTS_DIR/$run_group"
mkdir -p "$group_dir"
success_count=0
telemetry_pid=""
cleanup() {
  if [[ -n "$telemetry_pid" ]]; then
    kill "$telemetry_pid" 2>/dev/null || true
    wait "$telemetry_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

for n_cpu_moe in "${MOE_VALUES[@]}"; do
  printf '\n== Testing --n-cpu-moe %s ==\n' "$n_cpu_moe"
  capture_snapshot "$group_dir/ncmoe_${n_cpu_moe}_before.txt"
  nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu,pstate \
    --format=csv,noheader -lms 500 >"$group_dir/ncmoe_${n_cpu_moe}_gpu.csv" &
  telemetry_pid=$!
  if run_with_log "$group_dir/ncmoe_${n_cpu_moe}.log" \
    "$LLAMA_CLI" "${COMMON_ARGS[@]}" \
    --fit off -ngl all --n-cpu-moe "$n_cpu_moe" --no-mmap \
    -c "$BASE_CONTEXT" --single-turn --show-timings \
    -n "$N_PREDICT" -p "$PROMPT" "$@"; then
    printf 'PASS: --n-cpu-moe %s\n' "$n_cpu_moe"
    success_count=$((success_count + 1))
  else
    printf 'FAIL/OOM: --n-cpu-moe %s\n' "$n_cpu_moe"
  fi
  kill "$telemetry_pid" 2>/dev/null || true
  wait "$telemetry_pid" 2>/dev/null || true
  telemetry_pid=""
  capture_snapshot "$group_dir/ncmoe_${n_cpu_moe}_after.txt"
done

printf '\nResults: %s\n' "$group_dir"
grep -HE 'Generation:|CUDA.*buffer|out of memory|OOM' "$group_dir"/*.log || true
if (( success_count == 0 )); then
  printf 'No layer placement completed successfully.\n' >&2
  exit 1
fi
