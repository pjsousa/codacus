#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_cli
read_model_keys
require_command nvidia-smi
require_executable /usr/bin/time
trap stop_telemetry EXIT INT TERM

read -r -a context_values <<<"${CONTEXTS:-4096 10000}"
new_result_dir footprint
group_dir="$NEW_RESULT_DIR"
printf 'INCOMPLETE\n' >"$group_dir/group.status"
success_count=0
skip_count=0
prompt='In one sentence, distinguish model-file size from peak runtime memory.'

for key in "${MODEL_KEYS[@]}"; do
  if ! model_is_runnable "$key"; then
    skip_count=$((skip_count + 1))
    continue
  fi
  build_model_args "$key"
  for context in "${context_values[@]}"; do
    stem="${key}_ctx${context}"
    printf '\n== %s context %s ==\n' "$(model_label "$key")" "$context"
    capture_snapshot "$group_dir/${stem}_before.txt"
    start_telemetry "$group_dir/${stem}_gpu.csv"
    if run_capture_stdout "$group_dir/${stem}.log" "$group_dir/${stem}.txt" \
      "$LLAMA_CLI" "${MODEL_ARGS[@]}" "${GENERATION_ARGS[@]}" \
      -c "$context" -n 32 -p "$prompt" "$@"; then
      stop_telemetry
      capture_snapshot "$group_dir/${stem}_after.txt"
      if log_has_runtime_error "$group_dir/${stem}.log"; then
        printf 'FAIL hidden runtime error: %s\n' "$stem"
        break
      else
        peak_mib="$(peak_gpu_mib "$group_dir/${stem}_gpu.csv")"
        total_mib="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | sed -n '1p')"
        headroom_mib=$((total_mib - ${peak_mib%.*}))
        swap_before="$(awk '$1 == "Swap:" { print $3 }' "$group_dir/${stem}_before.txt")"
        swap_after="$(awk '$1 == "Swap:" { print $3 }' "$group_dir/${stem}_after.txt")"
        printf 'peak_vram_mib=%s headroom_mib=%s swap_before_bytes=%s swap_after_bytes=%s\n' \
          "$peak_mib" "$headroom_mib" "$swap_before" "$swap_after"
        if (( headroom_mib < GPU_MARGIN_MIB || swap_after > swap_before )); then
          printf 'FAIL memory margin/swap criterion: %s\n' "$stem"
          break
        fi
        printf 'PASS allocation/generation: %s\n' "$stem"
        success_count=$((success_count + 1))
      fi
    else
      stop_telemetry
      capture_snapshot "$group_dir/${stem}_after.txt"
      printf 'FAIL/OOM: %s\n' "$stem"
      break
    fi
  done
done

stop_telemetry
printf '\nEvidence: %s\n' "$group_dir"
printf 'Summary: successes=%s skipped_models=%s\n' "$success_count" "$skip_count"
if (( success_count == 0 )); then
  printf 'No context candidate succeeded.\n' >&2
  exit 1
fi
printf 'COMPLETE\n' >"$group_dir/group.status"
