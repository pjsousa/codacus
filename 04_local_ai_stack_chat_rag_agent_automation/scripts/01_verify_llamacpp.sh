#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

printf '=== Verifying existing llama.cpp build ===\n'

require_file "$LLAMA_CLI"
require_file "$LLAMA_SERVER"

printf 'CLI binary: %s\n' "$LLAMA_CLI"
"$LLAMA_CLI" --version

printf '\nServer binary: %s\n' "$LLAMA_SERVER"
"$LLAMA_SERVER" --version 2>&1 || true

printf '\n=== CUDA device detection ===\n'
"$LLAMA_CLI" --list-devices 2>&1 || printf '(--list-devices not supported in this build)\n'

printf '\n=== Testing llama-server startup ===\n'
require_model

PORT="${LLAMA_PORT:-8088}"
run_id="server_test_$(timestamp)"
log_file="$RESULTS_DIR/${run_id}.log"
mkdir -p "$RESULTS_DIR"

"$LLAMA_SERVER" \
  -m "$MODEL_PATH" \
  --no-mmproj \
  -t "$THREADS" \
  -tb "$THREADS_BATCH" \
  -c "$BASE_CONTEXT" \
  --flash-attn auto \
  --host 127.0.0.1 --port "$PORT" \
  >"$log_file" 2>&1 &
server_pid=$!

cleanup() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

printf 'Waiting for server to become ready on port %s...\n' "$PORT"
if ! wait_for_health "http://127.0.0.1:$PORT/health" 30; then
  printf 'FAIL: Server did not become healthy within 60 seconds.\n' >&2
  tail -30 "$log_file" >&2
  exit 1
fi
printf 'OK: Server is healthy.\n'

printf '\n=== Testing OpenAI-compatible endpoint ===\n'
response=$(curl --silent --fail --max-time 120 "http://127.0.0.1:$PORT/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{
    "messages":[{"role":"user","content":"Reply with exactly: hello from local AI"}],
    "max_tokens":16,
    "temperature":0
  }')
printf 'Response: %s\n' "$response"

printf '\n=== Testing /v1/models endpoint ===\n'
models=$(curl --silent --fail --max-time 10 "http://127.0.0.1:$PORT/v1/models")
printf 'Models: %s\n' "$models"

printf '\n=== Verification complete ===\n'
printf 'llama-server revision: %s\n' "$LLAMA_REV"
printf 'Server log: %s\n' "$log_file"
printf 'The OpenAI-compatible endpoint is ready at http://127.0.0.1:%s/v1\n' "$PORT"
