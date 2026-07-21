#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

require_file "$LLAMA_SERVER"
require_model

PORT="${LLAMA_PORT:-8080}"
HOST="${LLAMA_HOST:-127.0.0.1}"
run_id="server_$(timestamp)"
log_file="$RESULTS_DIR/${run_id}.log"
pid_file="$RESULTS_DIR/${run_id}.pid"

if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
  printf 'A server is already running (PID %s). Stop it first or use a different port.\n' "$(cat "$pid_file")" >&2
  exit 1
fi

capture_snapshot "$RESULTS_DIR/${run_id}_before.txt"

printf 'Starting llama-server on %s:%s\n' "$HOST" "$PORT"
printf 'Model: %s\n' "$MODEL_PATH"
printf 'Log: %s\n' "$log_file"

"$LLAMA_SERVER" \
  -m "$MODEL_PATH" \
  --no-mmproj \
  -t "$THREADS" \
  -tb "$THREADS_BATCH" \
  -c "$BASE_CONTEXT" \
  --flash-attn auto \
  --host "$HOST" --port "$PORT" \
  -ngl 99 \
  >"$log_file" 2>&1 &
server_pid=$!
printf '%s' "$server_pid" >"$pid_file"

trap 'kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true' EXIT

printf 'Waiting for server to become ready on %s:%s...\n' "$HOST" "$PORT"
if ! wait_for_health "http://$HOST:$PORT/health" 60; then
  printf 'FAIL: Server did not become healthy within 120 seconds.\n' >&2
  tail -50 "$log_file" >&2
  exit 1
fi

capture_snapshot "$RESULTS_DIR/${run_id}_after.txt"

printf '\n=== Server is running ===\n'
printf 'PID:      %s\n' "$server_pid"
printf 'Endpoint: http://%s:%s/v1\n' "$HOST" "$PORT"
printf 'Health:   http://%s:%s/health\n' "$HOST" "$PORT"
printf 'Log:      %s\n' "$log_file"
printf '\nTo stop the server:\n'
printf '  kill %s\n' "$server_pid"
printf '  rm -f %s\n' "$pid_file"
printf '\nVerify with:\n'
printf '  curl http://%s:%s/v1/models\n' "$HOST" "$PORT"
