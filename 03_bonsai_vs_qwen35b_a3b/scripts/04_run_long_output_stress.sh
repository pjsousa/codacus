#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_cli
read_model_keys
require_command python3
trap stop_telemetry EXIT INT TERM

STRESS_N_PREDICT="${STRESS_N_PREDICT:-4096}"
STRESS_RUNS="${STRESS_RUNS:-3}"
prompt='Return exactly one complete self-contained HTML document for an observability dashboard. Use inline CSS and one large inline SVG containing at least 120 explicitly written coordinate pairs across several polylines; do not use JavaScript to generate them. Include content after the SVG and close body and html. No external requests. Output HTML only. This intentionally tests reliable completion after a long repetitive coordinate section.'
new_result_dir long_output
group_dir="$NEW_RESULT_DIR"
printf 'INCOMPLETE\n' >"$group_dir/group.status"
success_count=0
required_count=0
incomplete_count=0

for key in "${MODEL_KEYS[@]}"; do
  if ! model_is_runnable "$key"; then
    incomplete_count=$((incomplete_count + STRESS_RUNS))
    continue
  fi
  build_model_args "$key"
  for ((run = 1; run <= STRESS_RUNS; run++)); do
    stem="${key}_run${run}"
    required_count=$((required_count + 1))
    printf '\n== %s run %s ==\n' "$(model_label "$key")" "$run"
    start_telemetry "$group_dir/${stem}_gpu.csv"
    if run_capture_stdout "$group_dir/${stem}.log" "$group_dir/${stem}.html" \
      "$LLAMA_CLI" "${MODEL_ARGS[@]}" "${GENERATION_ARGS[@]}" \
      -c "$CONTEXT_SIZE" -n "$STRESS_N_PREDICT" -p "$prompt" "$@"; then
      stop_telemetry
      if python3 -c 'import pathlib, re, sys; t=pathlib.Path(sys.argv[1]).read_text(errors="replace").strip(); sys.exit(0 if re.search(r"(?is)</html>\s*$", t) else 1)' "$group_dir/${stem}.html" \
        && ! log_has_runtime_error "$group_dir/${stem}.log"; then
        printf 'PASS completed document: %s\n' "$stem"
        success_count=$((success_count + 1))
      else
        printf 'FAIL incomplete or errored document: %s\n' "$stem"
        incomplete_count=$((incomplete_count + 1))
      fi
    else
      stop_telemetry
      printf 'FAIL process: %s\n' "$stem"
      incomplete_count=$((incomplete_count + 1))
    fi
  done
done

stop_telemetry
printf '\nEvidence: %s\n' "$group_dir"
if (( success_count == 0 )); then
  printf 'No long-output candidate produced a complete document.\n' >&2
  exit 1
fi
if (( incomplete_count > 0 || success_count != required_count )); then
  printf 'Stress matrix incomplete: passed=%s attempted=%s incomplete=%s.\n' "$success_count" "$required_count" "$incomplete_count" >&2
  exit 2
fi
printf 'COMPLETE\n' >"$group_dir/group.status"
