#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_file "$LLAMA_BENCH"
require_file "$MODEL_PATH"
prepare_results

run_group="benchmark_$(timestamp)"
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

run_bench() {
  local phase="$1"
  shift
  capture_snapshot "$group_dir/${phase}_before.txt"
  nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu,pstate \
    --format=csv,noheader -lms 500 >"$group_dir/${phase}_gpu.csv" &
  telemetry_pid=$!
  if run_with_log "$group_dir/${phase}.log" \
    "$LLAMA_BENCH" -m "$MODEL_PATH" -t "$THREADS" -p 128 -n 128 -r 3 "$@"; then
    printf 'PASS: %s\n' "$phase"
    success_count=$((success_count + 1))
  else
    printf 'FAIL: %s\n' "$phase"
  fi
  kill "$telemetry_pid" 2>/dev/null || true
  wait "$telemetry_pid" 2>/dev/null || true
  telemetry_pid=""
  capture_snapshot "$group_dir/${phase}_after.txt"
}

run_bench baseline -ngl "$BASELINE_NGL" -ncmoe 0 -mmp 1 -fa auto
run_bench moe_cpu -ngl 99 -ncmoe "$CPU_MOE_ALL" -mmp 1 -fa auto
run_bench no_mmap -ngl 99 -ncmoe "$CPU_MOE_ALL" -mmp 0 -fa auto
run_bench tuned_35 -ngl 99 -ncmoe "$CPU_MOE_TUNED" -mmp 0 -fa auto
run_bench tuned_36_safe_kv -ngl 99 -ncmoe "$CPU_MOE_LONG_CONTEXT" -mmp 0 \
  -fa auto -ctk q8_0 -ctv turbo3

report="$group_dir/summary.txt"
{
  printf 'Phase benchmark lines (pp=prompt processing, tg=token generation)\n'
  for log_file in "$group_dir"/*.log; do
    printf '\n== %s ==\n' "$(basename "$log_file" .log)"
    grep -E '^\|.*(pp128|tg128)' "$log_file" || true
    grep -E 'Maximum resident set size' "$log_file" || true
  done
} >"$report"

printf 'Benchmark package: %s\nSummary: %s\n' "$group_dir" "$report"
if (( success_count == 0 )); then
  printf 'Every benchmark phase failed.\n' >&2
  exit 1
fi
