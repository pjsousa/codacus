#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_engine
require_command curl
require_command jq
curl_auth_args

ROUTER_START_TIMEOUT="${ROUTER_START_TIMEOUT:-60}"
MODEL_LOAD_TIMEOUT="${MODEL_LOAD_TIMEOUT:-900}"

mkdir -p "$STACK_DIR/presets"

# Regenerate the router preset from the current configuration on every run so
# config.env edits take effect. Keys mirror llama-server long arguments.
# Note: on this build a "version = 1" preamble is parsed as an extra bogus
# "default" preset (verified 2026-07-22), so the file starts directly with
# the named section.
{
  printf '[%s]\n' "$MODEL_ALIAS"
  printf 'model = %s\n' "$MODEL_PATH"
  printf 'no-mmproj = true\n'
  printf 'fit = off\n'
  printf 'n-gpu-layers = %s\n' "$ENGINE_NGL"
  printf 'n-cpu-moe = %s\n' "$ENGINE_CPU_MOE"
  printf 'cache-type-k = %s\n' "$ENGINE_CACHE_K"
  printf 'cache-type-v = %s\n' "$ENGINE_CACHE_V"
  printf 'ctx-size = %s\n' "$ENGINE_CTX"
  printf 'threads = %s\n' "$THREADS"
  printf 'threads-batch = %s\n' "$THREADS_BATCH"
  printf 'flash-attn = auto\n'
  if [[ "$ENGINE_NO_MMAP" == "1" ]]; then
    printf 'no-mmap = true\n'
  fi
  if [[ "$ENGINE_MLOCK" == "1" ]]; then
    printf 'mlock = true\n'
  fi
} >"$PRESET_FILE"
printf 'Wrote router preset: %s\n' "$PRESET_FILE"

if [[ -f "$ENGINE_PID_FILE" ]] && kill -0 "$(cat "$ENGINE_PID_FILE")" 2>/dev/null; then
  printf 'Engine already running (PID %s). Run scripts/09_stop_stack.sh first to restart it.\n' \
    "$(cat "$ENGINE_PID_FILE")"
  exit 0
fi
rm -f "$ENGINE_PID_FILE"

require_port_free "$ROUTER_PORT"

run_id="engine_$(timestamp)"
log_file="$RESULTS_DIR/${run_id}.log"
capture_snapshot "$RESULTS_DIR/${run_id}_before.txt"

router_args=(
  --host "$ROUTER_HOST"
  --port "$ROUTER_PORT"
  --models-preset "$PRESET_FILE"
  --models-max "$MODELS_MAX"
)
if [[ "$SLEEP_IDLE_SECONDS" != "-1" ]]; then
  router_args+=(--sleep-idle-seconds "$SLEEP_IDLE_SECONDS")
fi
if [[ -n "$LLAMA_API_KEY" ]]; then
  router_args+=(--api-key "$LLAMA_API_KEY")
fi

server_pid=""
cleanup_on_error() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    rm -f "$ENGINE_PID_FILE"
    printf 'Engine start failed and was rolled back; inspect %s\n' "$log_file" >&2
  fi
}
trap cleanup_on_error ERR

log_command "$log_file" "$LLAMA_SERVER" "${router_args[@]}" "$@"
nohup "$LLAMA_SERVER" "${router_args[@]}" "$@" >>"$log_file" 2>&1 &
server_pid=$!
printf '%s\n' "$server_pid" >"$ENGINE_PID_FILE"

printf 'Waiting for the router on %s ...\n' "$ENGINE_BASE_URL"
if ! wait_http "$ENGINE_BASE_URL/v1/models" "$ROUTER_START_TIMEOUT" "${CURL_AUTH_ARGS[@]}"; then
  printf 'Router did not start; inspect %s\n' "$log_file" >&2
  exit 1
fi

printf 'Requesting load of preset "%s" (first load reads about 21 GB)...\n' "$MODEL_ALIAS"
curl --silent --max-time 30 "${CURL_AUTH_ARGS[@]}" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL_ALIAS\"}" \
  "$ENGINE_BASE_URL/models/load" || true

load_deadline=$((SECONDS + MODEL_LOAD_TIMEOUT))
model_status="unknown"
while (( SECONDS < load_deadline )); do
  model_status="$(curl --silent --max-time 10 "${CURL_AUTH_ARGS[@]}" \
    "$ENGINE_BASE_URL/v1/models" 2>/dev/null \
    | jq -r --arg id "$MODEL_ALIAS" '.data[]? | select(.id == $id) | .status.value // empty' \
    | head -n1)"
  if [[ "$model_status" == "loaded" ]]; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    printf 'Engine process exited while loading; inspect %s\n' "$log_file" >&2
    exit 1
  fi
  sleep 5
done

if [[ "$model_status" != "loaded" ]]; then
  printf 'Model did not reach "loaded" status (last: %s); inspect %s\n' "$model_status" "$log_file" >&2
  exit 1
fi

response_file="$RESULTS_DIR/${run_id}_smoke.json"
http_code="$(curl --silent --max-time 300 "${CURL_AUTH_ARGS[@]}" \
  -H 'Content-Type: application/json' \
  -o "$response_file" -w '%{http_code}' \
  -d "$(jq -nc --arg model "$MODEL_ALIAS" --arg prompt "$SMOKE_PROMPT" \
    '{model:$model,messages:[{role:"user",content:$prompt}],max_tokens:'"$SMOKE_MAX_TOKENS"',temperature:0,seed:42}')" \
  "$ENGINE_BASE_URL/v1/chat/completions")"

if [[ "$http_code" != "200" ]]; then
  printf 'Smoke chat completion returned HTTP %s; inspect %s and %s\n' \
    "$http_code" "$response_file" "$log_file" >&2
  exit 1
fi

printf 'Smoke response: %s\n' "$(jq -r '.choices[0].message.content' "$response_file")"
jq '{model, usage, timings: .timings // empty}' "$response_file" || true
capture_snapshot "$RESULTS_DIR/${run_id}_after.txt"
trap - ERR

printf '\nEngine is up: %s (preset "%s", log %s)\n' "$ENGINE_BASE_URL" "$MODEL_ALIAS" "$log_file"
printf 'PID %s recorded in %s. Stop with scripts/09_stop_stack.sh.\n' "$server_pid" "$ENGINE_PID_FILE"
