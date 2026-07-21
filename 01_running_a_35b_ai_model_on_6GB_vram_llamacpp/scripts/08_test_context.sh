#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_runtime

CACHE_PROFILE="${CACHE_PROFILE:-safe}"
case "$CACHE_PROFILE" in
  video)
    CACHE_K=turbo4
    CACHE_V=turbo3
    ;;
  safe)
    CACHE_K=q8_0
    CACHE_V=turbo3
    ;;
  upstream)
    CACHE_K=q8_0
    CACHE_V=q8_0
    ;;
  *)
    printf 'Unknown CACHE_PROFILE=%s; use video, safe, or upstream.\n' "$CACHE_PROFILE" >&2
    exit 1
    ;;
esac

read -r -a CONTEXTS <<<"${CONTEXTS:-65536 131072 262144}"
run_group="context_${CACHE_PROFILE}_$(timestamp)"
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

for context in "${CONTEXTS[@]}"; do
  n_cpu_moe="$CPU_MOE_TUNED"
  if (( context >= 262144 )); then
    n_cpu_moe="$CPU_MOE_LONG_CONTEXT"
  fi
  printf '\n== Testing context=%s K=%s V=%s n-cpu-moe=%s ==\n' \
    "$context" "$CACHE_K" "$CACHE_V" "$n_cpu_moe"
  capture_snapshot "$group_dir/ctx_${context}_before.txt"
  nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu,pstate \
    --format=csv,noheader -lms 500 >"$group_dir/ctx_${context}_gpu.csv" &
  telemetry_pid=$!
  if run_with_log "$group_dir/ctx_${context}.log" \
    "$LLAMA_CLI" "${COMMON_ARGS[@]}" \
    --fit off -ngl all --n-cpu-moe "$n_cpu_moe" --no-mmap \
    --cache-type-k "$CACHE_K" --cache-type-v "$CACHE_V" \
    -c "$context" --single-turn --show-timings -n 32 -p "$PROMPT" "$@"; then
    printf 'PASS: context %s allocated and generated tokens.\n' "$context"
    success_count=$((success_count + 1))
  else
    printf 'FAIL/OOM: context %s.\n' "$context"
  fi
  kill "$telemetry_pid" 2>/dev/null || true
  wait "$telemetry_pid" 2>/dev/null || true
  telemetry_pid=""
  capture_snapshot "$group_dir/ctx_${context}_after.txt"
done

printf 'Context results: %s\n' "$group_dir"
if (( success_count == 0 )); then
  printf 'No context allocation completed successfully.\n' >&2
  exit 1
fi

if [[ "${RUN_RETRIEVAL:-0}" == "1" ]]; then
  require_file "$LLAMA_COMPLETION"
  retrieval_failures=0
  for context in "${CONTEXTS[@]}"; do
    n_cpu_moe="$CPU_MOE_TUNED"
    if (( context >= 262144 )); then
      n_cpu_moe="$CPU_MOE_LONG_CONTEXT"
    fi
    prompt_file="$group_dir/retrieval_${context}.txt"
    python3 - "$prompt_file" "$context" <<'PY'
import sys

path = sys.argv[1]
context = int(sys.argv[2])
n_filler = int(context * 0.80)
needle_position = int(n_filler * 0.75)
with open(path, "w", encoding="ascii") as output:
    output.write("Find and remember the hidden pass key.")
    output.write(" grass" * needle_position)
    output.write(" The pass key is 31415. Remember that 31415 is the pass key.")
    output.write(" grass" * (n_filler - needle_position))
    output.write(" What is the pass key? The pass key is")
PY
    nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu,pstate \
      --format=csv,noheader -lms 500 >"$group_dir/retrieval_${context}_gpu.csv" &
    telemetry_pid=$!
    if run_with_log "$group_dir/retrieval_${context}.log" \
      "$LLAMA_COMPLETION" -m "$MODEL_PATH" \
      --fit off -ngl all --n-cpu-moe "$n_cpu_moe" --no-mmap \
      --cache-type-k "$CACHE_K" --cache-type-v "$CACHE_V" \
      -t "$THREADS" -tb "$THREADS_BATCH" --flash-attn auto \
      -c "$context" -f "$prompt_file" --no-conversation \
      --no-display-prompt --no-context-shift --temperature 0 --seed 42 -n 16; then
      if grep -q '31415' "$group_dir/retrieval_${context}.log"; then
        printf 'PASS: context %s retrieved the fixed key.\n' "$context"
      else
        printf 'FAIL: context %s generated but did not retrieve the fixed key.\n' "$context"
        retrieval_failures=$((retrieval_failures + 1))
      fi
    else
      printf 'FAIL: context %s retrieval command failed.\n' "$context"
      retrieval_failures=$((retrieval_failures + 1))
    fi
    kill "$telemetry_pid" 2>/dev/null || true
    wait "$telemetry_pid" 2>/dev/null || true
    telemetry_pid=""
  done
  if (( retrieval_failures > 0 )); then
    exit 1
  fi
fi
