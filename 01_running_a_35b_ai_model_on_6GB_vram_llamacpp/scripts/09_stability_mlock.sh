#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_runtime
require_file "$LLAMA_SERVER"
require_command curl

soft_limit="$(ulimit -Sl)"
hard_limit="$(ulimit -Hl)"
if [[ "$soft_limit" != "unlimited" ]] || [[ "$hard_limit" != "unlimited" ]]; then
  printf 'Cannot validate --mlock: soft=%s KiB hard=%s KiB.\n' "$soft_limit" "$hard_limit" >&2
  printf 'Raise both limits to unlimited, start a new login session, and rerun. See GUIDE.md.\n' >&2
  exit 1
fi

PORT="${PORT:-8088}"
run_id="mlock_$(timestamp)"
log_file="$RESULTS_DIR/${run_id}.log"
status_file="$RESULTS_DIR/${run_id}_proc_status.txt"
response_file="$RESULTS_DIR/${run_id}_response.json"
telemetry_file="$RESULTS_DIR/${run_id}_telemetry.csv"
STABILITY_SECONDS="${STABILITY_SECONDS:-0}"
STABILITY_INTERVAL="${STABILITY_INTERVAL:-300}"

"$LLAMA_SERVER" "${COMMON_ARGS[@]}" \
  --fit off -ngl all --n-cpu-moe "$CPU_MOE_TUNED" --no-mmap --mlock \
  --cache-type-k q8_0 --cache-type-v turbo3 -c "$BASE_CONTEXT" \
  --host 127.0.0.1 --port "$PORT" >"$log_file" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT

ready=0
for _ in $(seq 1 180); do
  if curl --silent --fail "http://127.0.0.1:$PORT/health" >/dev/null; then
    ready=1
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [[ "$ready" != "1" ]]; then
  printf 'Server did not become ready; inspect %s\n' "$log_file" >&2
  exit 1
fi

grep -E '^(VmLck|VmPin):' "/proc/$server_pid/status" | tee "$status_file"
grep 'Max locked memory' "/proc/$server_pid/limits" | tee -a "$status_file"
read -r _ vmlck_kib _ < <(grep '^VmLck:' "/proc/$server_pid/status")
if (( vmlck_kib < 1048576 )); then
  printf 'FAIL: only %s KiB is locked; expected at least 1 GiB.\n' "$vmlck_kib" >&2
  exit 1
fi

request_once() {
  local response
  if ! response="$(curl --silent --fail --max-time 600 "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"Reply with exactly: stability check passed"}],"max_tokens":32,"temperature":0}')"; then
    return 1
  fi
  printf '{"timestamp":"%s","response":%s}\n' \
    "$(date -u +%FT%TZ)" "$response" >>"$response_file"
}

request_once

if (( STABILITY_SECONDS > 0 )); then
  printf 'timestamp,vmrss_kib,vmlck_kib,vmswap_kib,major_faults,gpu_memory_mib\n' >"$telemetry_file"
  end_time=$((SECONDS + STABILITY_SECONDS))
  request_failures=0
  while (( SECONDS < end_time )); do
    sleep "$STABILITY_INTERVAL"
    if ! kill -0 "$server_pid" 2>/dev/null; then
      printf 'Server exited during stability soak.\n' >&2
      exit 1
    fi
    read -r _ vmrss_kib _ < <(grep '^VmRSS:' "/proc/$server_pid/status")
    read -r _ vmlck_kib _ < <(grep '^VmLck:' "/proc/$server_pid/status")
    read -r _ vmswap_kib _ < <(grep '^VmSwap:' "/proc/$server_pid/status")
    read -r -a proc_stat <"/proc/$server_pid/stat"
    major_faults="${proc_stat[11]}"
    read -r gpu_memory_mib < <(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
    printf '%s,%s,%s,%s,%s,%s\n' "$(date -u +%FT%TZ)" \
      "$vmrss_kib" "$vmlck_kib" "$vmswap_kib" "$major_faults" "$gpu_memory_mib" \
      >>"$telemetry_file"
    if ! request_once; then
      request_failures=$((request_failures + 1))
    fi
  done
  if (( request_failures > 0 )); then
    printf '%s stability requests failed; inspect %s\n' "$request_failures" "$response_file" >&2
    exit 1
  fi
fi

printf 'mlock validation complete: %s\n' "$status_file"
if (( STABILITY_SECONDS > 0 )); then
  printf 'Stability telemetry: %s\n' "$telemetry_file"
fi
