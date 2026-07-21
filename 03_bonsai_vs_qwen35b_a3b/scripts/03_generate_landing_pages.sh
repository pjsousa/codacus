#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_cli
read_model_keys
trap stop_telemetry EXIT INT TERM

LANDING_N_PREDICT="${LANDING_N_PREDICT:-4096}"
prompt='Create one polished landing page for a fictional local-first infrastructure assistant named Relay. Return exactly one complete, self-contained HTML file. Use inline CSS and inline SVG only. Make no external requests: no CDN, web fonts, image URLs, scripts, or linked stylesheets. It must remain usable at a 390px phone width. Include a hero, product visualization, three concrete capabilities, one testimonial, pricing, and a final call to action. Output HTML only, beginning with <!doctype html> and ending with </html>.'
new_result_dir landing
group_dir="$NEW_RESULT_DIR"
printf 'INCOMPLETE\n' >"$group_dir/group.status"
success_count=0
incomplete_count=0

for key in "${MODEL_KEYS[@]}"; do
  printf '\n== %s ==\n' "$(model_label "$key")"
  if ! model_is_runnable "$key"; then
    incomplete_count=$((incomplete_count + 1))
    continue
  fi
  build_model_args "$key"
  capture_snapshot "$group_dir/${key}_before.txt"
  start_telemetry "$group_dir/${key}_gpu.csv"
  if run_capture_stdout "$group_dir/${key}.log" "$group_dir/${key}.html" \
    "$LLAMA_CLI" "${MODEL_ARGS[@]}" "${GENERATION_ARGS[@]}" \
    -c "$CONTEXT_SIZE" -n "$LANDING_N_PREDICT" --seed "$SEED" -p "$prompt" "$@"; then
    stop_telemetry
    capture_snapshot "$group_dir/${key}_after.txt"
    if log_has_runtime_error "$group_dir/${key}.log"; then
      printf 'FAIL %s: runtime error text found despite process status.\n' "$key"
      incomplete_count=$((incomplete_count + 1))
    else
      printf 'PASS process: %s\n' "$key"
      success_count=$((success_count + 1))
    fi
  else
    stop_telemetry
    capture_snapshot "$group_dir/${key}_after.txt"
      printf 'FAIL process: %s\n' "$key"
      incomplete_count=$((incomplete_count + 1))
  fi
done

stop_telemetry
printf '\nEvidence: %s\n' "$group_dir"
if (( success_count == 0 )); then
  printf 'No configured model completed the landing-page run.\n' >&2
  exit 1
fi
if (( incomplete_count > 0 )); then
  printf 'Comparison incomplete: %s selected model(s) skipped or failed.\n' "$incomplete_count" >&2
  exit 2
fi
printf 'COMPLETE\n' >"$group_dir/group.status"
