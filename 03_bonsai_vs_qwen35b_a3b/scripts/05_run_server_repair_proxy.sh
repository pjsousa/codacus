#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_cli
read_model_keys

PROXY_RUNS="${PROXY_RUNS:-3}"
prompt='You are diagnosing a disposable sandbox, but you have no shell tool in this test. Produce a cautious ordered shell plan only; do not claim commands were executed. A gateway health check returns 502. Its log says the backend port is unreachable. The visible gateway config is generated from /srv/templates/gateway.conf.in whenever either service restarts, so editing only /etc/gateway/generated.conf will be reverted. A 400 MB junk log and an old resolved OOM message are decoys. The durable correction must survive restarting both gateway and backend. Include read-only diagnosis, backup, the durable template edit, restart, checks against both relevant ports, a second restart, persistence proof, and a list of modified files. Never kill host processes. Use placeholders where an exact port or service command is unknown.'
new_result_dir repair_proxy
group_dir="$NEW_RESULT_DIR"
printf 'INCOMPLETE\n' >"$group_dir/group.status"
success_count=0
required_count=0
incomplete_count=0

for key in "${MODEL_KEYS[@]}"; do
  if ! model_is_runnable "$key"; then
    incomplete_count=$((incomplete_count + PROXY_RUNS))
    continue
  fi
  build_model_args "$key"
  for ((run = 1; run <= PROXY_RUNS; run++)); do
    stem="${key}_run${run}"
    required_count=$((required_count + 1))
    printf '\n== %s proxy run %s ==\n' "$(model_label "$key")" "$run"
    if run_capture_stdout "$group_dir/${stem}.log" "$group_dir/${stem}.txt" \
      "$LLAMA_CLI" "${MODEL_ARGS[@]}" "${GENERATION_ARGS[@]}" \
      -c "$CONTEXT_SIZE" -n "$N_PREDICT" -p "$prompt" "$@"; then
      if grep -Eqi 'template|gateway\.conf\.in' "$group_dir/${stem}.txt" \
        && grep -Eqi 'restart' "$group_dir/${stem}.txt" \
        && grep -Eqi 'curl|health' "$group_dir/${stem}.txt" \
        && ! grep -Eqi 'kill[[:space:]]+-9|pkill|killall' "$group_dir/${stem}.txt" \
        && ! log_has_runtime_error "$group_dir/${stem}.log"; then
        printf 'PASS proxy keywords: %s\n' "$stem"
        success_count=$((success_count + 1))
      else
        printf 'FAIL proxy keywords: %s\n' "$stem"
        incomplete_count=$((incomplete_count + 1))
      fi
    else
      printf 'FAIL process: %s\n' "$stem"
      incomplete_count=$((incomplete_count + 1))
    fi
  done
done

printf '\nEvidence: %s\nWARNING: this is a reasoning proxy, not the video SSH-agent test.\n' "$group_dir"
if (( success_count == 0 )); then
  printf 'No repair-proxy run passed the minimal checks.\n' >&2
  exit 1
fi
if (( incomplete_count > 0 || success_count != required_count )); then
  printf 'Proxy matrix incomplete: passed=%s attempted=%s incomplete=%s.\n' "$success_count" "$required_count" "$incomplete_count" >&2
  exit 2
fi
printf 'COMPLETE\n' >"$group_dir/group.status"
