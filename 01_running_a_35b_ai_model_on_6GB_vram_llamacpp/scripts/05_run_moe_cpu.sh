#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_runtime

run_id="moe_cpu_$(timestamp)"
capture_snapshot "$RESULTS_DIR/${run_id}_before.txt"
run_with_log "$RESULTS_DIR/${run_id}.log" \
  "$LLAMA_CLI" "${COMMON_ARGS[@]}" \
  --fit off -ngl all --n-cpu-moe "$CPU_MOE_ALL" -c "$BASE_CONTEXT" \
  --single-turn --show-timings -n "$N_PREDICT" -p "$PROMPT" "$@"
capture_snapshot "$RESULTS_DIR/${run_id}_after.txt"

printf 'All-experts-on-CPU phase complete: %s/%s.log\n' "$RESULTS_DIR" "$run_id"
