#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_bench
read_model_keys
require_command nvidia-smi
require_command jq
require_executable /usr/bin/time
trap stop_telemetry EXIT INT TERM

BENCH_PROMPT_TOKENS="${BENCH_PROMPT_TOKENS:-512}"
BENCH_GEN_TOKENS="${BENCH_GEN_TOKENS:-128}"
BENCH_REPETITIONS="${BENCH_REPETITIONS:-3}"
new_result_dir benchmark
group_dir="$NEW_RESULT_DIR"
printf 'INCOMPLETE\n' >"$group_dir/group.status"
success_count=0
incomplete_count=0

for key in "${MODEL_KEYS[@]}"; do
  if ! model_is_runnable "$key"; then
    incomplete_count=$((incomplete_count + 1))
    continue
  fi
  path="$(model_path "$key")"
  bench_args=(-m "$path" -t "$THREADS" -p "$BENCH_PROMPT_TOKENS" -n "$BENCH_GEN_TOKENS" \
    -r "$BENCH_REPETITIONS" -fa auto -ctk "$KV_CACHE_K" -ctv "$KV_CACHE_V" -o jsonl)
  case "$key" in
    qwen) bench_args+=(-ngl 99 -ncmoe "$QWEN_N_CPU_MOE" -mmp 1) ;;
    binary) bench_args+=(-ngl 99 -mmp 1) ;;
    ternary|gemma) bench_args+=(-ngl 99 -fitt "$GPU_MARGIN_MIB" -mmp 1) ;;
  esac

  printf '\n== Benchmark %s ==\n' "$(model_label "$key")"
  capture_snapshot "$group_dir/${key}_before.txt"
  start_telemetry "$group_dir/${key}_gpu.csv"
  if run_capture_stdout "$group_dir/${key}.log" "$group_dir/${key}.jsonl" "$LLAMA_BENCH" "${bench_args[@]}" "$@"; then
    stop_telemetry
    capture_snapshot "$group_dir/${key}_after.txt"
    if ! jq -e -s --argjson pp "$BENCH_PROMPT_TOKENS" --argjson tg "$BENCH_GEN_TOKENS" \
      'length == 2
       and any(.[]; .n_prompt == $pp and .n_gen == 0 and (.avg_ts | type) == "number")
       and any(.[]; .n_prompt == 0 and .n_gen == $tg and (.avg_ts | type) == "number")' \
      "$group_dir/${key}.jsonl" >/dev/null; then
      printf 'FAIL invalid/incomplete benchmark JSONL: %s\n' "$key"
      incomplete_count=$((incomplete_count + 1))
    elif log_has_runtime_error "$group_dir/${key}.log"; then
      printf 'FAIL hidden runtime error: %s\n' "$key"
      incomplete_count=$((incomplete_count + 1))
    else
      printf 'PASS benchmark: %s\n' "$key"
      success_count=$((success_count + 1))
    fi
  else
    stop_telemetry
    capture_snapshot "$group_dir/${key}_after.txt"
    printf 'FAIL benchmark: %s\n' "$key"
    incomplete_count=$((incomplete_count + 1))
  fi
done

stop_telemetry
if (( success_count == 0 )); then
  printf '\nEvidence: %s\n' "$group_dir"
  printf 'No benchmark candidate succeeded.\n' >&2
  exit 1
fi
summary="$group_dir/summary.tsv"
resources="$group_dir/resources.tsv"
printf 'model\ttest\tavg_tokens_per_second\tstddev_tokens_per_second\n' >"$summary"
printf 'model\tmaximum_rss_kib\tpeak_gpu_mib\n' >"$resources"
for json_file in "$group_dir"/*.jsonl; do
  jq -r '[.model_filename, (if .n_prompt > 0 then "pp" + (.n_prompt|tostring) else "tg" + (.n_gen|tostring) end), .avg_ts, .stddev_ts] | @tsv' \
    "$json_file" >>"$summary"
done
for key in "${MODEL_KEYS[@]}"; do
  if [[ -f "$group_dir/${key}.log" && -f "$group_dir/${key}_gpu.csv" ]]; then
    rss_kib="$(awk -F: '/Maximum resident set size/ { gsub(/[[:space:]]/, "", $2); print $2 }' "$group_dir/${key}.log" | sed -n '1p')"
    printf '%s\t%s\t%s\n' "$key" "${rss_kib:-TBD}" "$(peak_gpu_mib "$group_dir/${key}_gpu.csv")" >>"$resources"
  fi
done
printf '\nComparison summary:\n'
cat "$summary"
printf '\nResource summary:\n'
cat "$resources"
printf '\nEvidence: %s\n' "$group_dir"
if (( incomplete_count > 0 )); then
  printf 'Benchmark matrix incomplete: %s selected model(s) skipped or failed.\n' "$incomplete_count" >&2
  exit 2
fi
printf 'COMPLETE\n' >"$group_dir/group.status"
